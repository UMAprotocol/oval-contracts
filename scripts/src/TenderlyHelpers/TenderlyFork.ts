// Manages Tenderly forks.
// Requires environment variables TENDERLY_USER, TENDERLY_PROJECT and TENDERLY_ACCESS_KEY to be set, check:
// - https://docs.tenderly.co/other/platform-access/how-to-find-the-project-slug-username-and-organization-name
// - https://docs.tenderly.co/other/platform-access/how-to-generate-api-access-tokens

import axios from "axios";
import { BigNumber, providers, utils } from "ethers";

import { processEnvironment, TenderlyEnvironment } from "./TenderlySimulation";

const axiosInstance = axios.create({
  validateStatus: (status) => status >= 200 && status < 300,
});

// Fork parameters passed by the caller.
export interface TenderlyForkParams {
  chainId: number;
  blockNumber?: number;
  txIndex?: number;
  alias?: string;
  description?: string;
}

// We only type Tenderly fork API request properties that we use.
interface TenderlyForkRequestBody {
  network_id: string;
  block_number?: number;
  transaction_index?: number;
  alias?: string;
  description?: string;
}

// We only type Tenderly fork API response properties that we use.
interface TenderlyForkAPIResponse {
  simulation_fork: {
    id: string;
    block_number: number;
    transaction_index: number;
    accounts: Record<string, string>;
    global_head?: string; // Available only if there were any interactions with the fork.
    rpc_url: string;
  };
  root_transaction?: { id: string }; // Available only when creating new fork.
}

// Fork properties returned to the caller.
export interface TenderlyForkResult {
  id: string;
  blockNumber: number;
  txIndex: number;
  accounts: { address: string; privateKey: string }[];
  rpcUrl: string;
  headId?: string;
}

const validateForkParams = (forkParams: TenderlyForkParams): void => {
  if (!Number.isInteger(forkParams.chainId) || forkParams.chainId <= 0)
    throw new Error(`Invalid chainId: ${forkParams.chainId}`);
  if (
    forkParams.blockNumber !== undefined &&
    (!Number.isInteger(forkParams.blockNumber) || forkParams.blockNumber < 0)
  )
    throw new Error(`Invalid blockNumber: ${forkParams.blockNumber}`);
  if (forkParams.blockNumber === undefined && forkParams.txIndex !== undefined)
    throw new Error(`txIndex cannot be specified without blockNumber`);
  if (
    forkParams.txIndex !== undefined &&
    (!Number.isInteger(forkParams.txIndex) || forkParams.txIndex < 0)
  )
    throw new Error(`Invalid txIndex: ${forkParams.txIndex}`);
};

const createForkRequestBody = (
  forkParams: TenderlyForkParams
): TenderlyForkRequestBody => {
  const body: TenderlyForkRequestBody = {
    network_id: forkParams.chainId.toString(),
  };

  if (forkParams.blockNumber !== undefined)
    body.block_number = forkParams.blockNumber;
  if (forkParams.txIndex !== undefined)
    body.transaction_index = forkParams.txIndex;
  if (forkParams.alias !== undefined) body.alias = forkParams.alias;
  if (forkParams.description !== undefined)
    body.description = forkParams.description;

  return body;
};

function isTenderlySimulationFork(
  simulationFork: any
): simulationFork is TenderlyForkAPIResponse["simulation_fork"] {
  if (
    typeof simulationFork.id === "string" &&
    typeof simulationFork.block_number === "number" &&
    typeof simulationFork.transaction_index === "number" &&
    typeof simulationFork.accounts === "object" &&
    Object.keys(simulationFork.accounts).every(
      (key) => typeof key === "string"
    ) &&
    Object.values(simulationFork.accounts).every(
      (value) => typeof value === "string"
    ) &&
    typeof simulationFork.rpc_url === "string" &&
    ("global_head" in simulationFork
      ? typeof simulationFork.global_head === "string"
      : true) // Optional property
  ) {
    return true;
  }
  return false;
}

// Type guard function to check if the API response conforms to the required TenderlyForkAPIResponse interface
function isTenderlyForkAPIResponse(
  response: any
): response is TenderlyForkAPIResponse {
  if (
    response &&
    response.simulation_fork &&
    isTenderlySimulationFork(response.simulation_fork) &&
    ("root_transaction" in response
      ? typeof response.root_transaction === "object" &&
        typeof response.root_transaction.id === "string"
      : true) // Optional property
  ) {
    return true;
  }
  return false;
}

const getForkResponse = async (
  forkParams: TenderlyForkParams,
  tenderlyEnv: TenderlyEnvironment
): Promise<TenderlyForkAPIResponse> => {
  // Construct Tenderly fork API request.
  const url = `https://api.tenderly.co/api/v1/account/${tenderlyEnv.user}/project/${tenderlyEnv.project}/fork`;
  const body = createForkRequestBody(forkParams);
  const headers = { "X-Access-Key": tenderlyEnv.apiKey };

  // Send Tenderly fork API request (Axios will throw if the HTTP response is not valid).
  const response = await axiosInstance.post(url, body, { headers });

  // If the HTTP response was valid, we expect the response body should be a JSON object containing expected Tenderly
  // fork response properties.
  if (!isTenderlyForkAPIResponse(response.data)) {
    throw new Error(
      `Failed to parse Tenderly fork API response: ${JSON.stringify(
        response.data
      )}`
    );
  }

  return response.data;
};

const postForkSharing = async (
  forkId: string,
  share: boolean,
  tenderlyEnv: TenderlyEnvironment
): Promise<void> => {
  // Construct Tenderly fork API request.
  const cmd = share ? "share" : "unshare";
  const url = `https://api.tenderly.co/api/v1/account/${tenderlyEnv.user}/project/${tenderlyEnv.project}/fork/${forkId}/${cmd}`;
  const headers = { "X-Access-Key": tenderlyEnv.apiKey };

  // Send Tenderly fork API request (Axios will throw if the HTTP response is not valid).
  await axiosInstance.post(url, {}, { headers });
};

const forkAPIResponseToResult = (
  forkResponse: TenderlyForkAPIResponse
): TenderlyForkResult => {
  return {
    id: forkResponse.simulation_fork.id,
    blockNumber: forkResponse.simulation_fork.block_number,
    txIndex: forkResponse.simulation_fork.transaction_index,
    accounts: Object.entries(forkResponse.simulation_fork.accounts).map(
      ([address, privateKey]) => ({ address, privateKey })
    ),
    rpcUrl: forkResponse.simulation_fork.rpc_url,
    headId:
      forkResponse.simulation_fork.global_head ||
      forkResponse.root_transaction?.id,
  };
};

export const createTenderlyFork = async (
  forkParams: TenderlyForkParams
): Promise<TenderlyForkResult> => {
  // Will throw if required environment variables are not set.
  const tenderlyEnv = processEnvironment();

  // Will throw if fork parameters are invalid.
  validateForkParams(forkParams);

  // Will throw if Tenderly API request fails or returns unparsable response.
  const forkResponse = await getForkResponse(forkParams, tenderlyEnv);

  return forkAPIResponseToResult(forkResponse);
};

export const getTenderlyFork = async (
  forkId: string
): Promise<TenderlyForkResult> => {
  // Will throw if required environment variables are not set.
  const tenderlyEnv = processEnvironment();

  // Construct Tenderly fork API request.
  const url = `https://api.tenderly.co/api/v1/account/${tenderlyEnv.user}/project/${tenderlyEnv.project}/fork/${forkId}`;
  const headers = { "X-Access-Key": tenderlyEnv.apiKey };

  // Send Tenderly fork API request (Axios will throw if the HTTP response is not valid).
  const response = await axiosInstance.get(url, { headers });

  // If the HTTP response was valid, we expect the response body should be a JSON object containing expected Tenderly fork
  // response properties.
  if (!isTenderlyForkAPIResponse(response.data)) {
    throw new Error(
      `Failed to parse Tenderly fork API response: ${JSON.stringify(
        response.data
      )}`
    );
  }

  return forkAPIResponseToResult(response.data);
};

export const shareTenderlyFork = async (forkId: string): Promise<string> => {
  // Will throw if required environment variables are not set.
  const tenderlyEnv = processEnvironment();

  await postForkSharing(forkId, true, tenderlyEnv);

  // Return the Tenderly dashboard URL for the shared fork.
  return `https://dashboard.tenderly.co/shared/fork/${forkId}/transactions`;
};

export const unshareTenderlyFork = async (forkId: string): Promise<void> => {
  // Will throw if required environment variables are not set.
  const tenderlyEnv = processEnvironment();

  await postForkSharing(forkId, false, tenderlyEnv);
};

export const deleteTenderlyFork = async (forkId: string): Promise<void> => {
  // Will throw if required environment variables are not set.
  const tenderlyEnv = processEnvironment();

  // Construct Tenderly fork API request.
  const url = `https://api.tenderly.co/api/v1/account/${tenderlyEnv.user}/project/${tenderlyEnv.project}/fork/${forkId}`;
  const headers = { "X-Access-Key": tenderlyEnv.apiKey };

  // Send Tenderly fork API request (Axios will throw if the HTTP response is not valid).
  await axiosInstance.delete(url, { headers });
};

export const setTenderlyBalance = async (
  forkId: string,
  address: string,
  balance: string // Amount in wei.
): Promise<string> => {
  // Will throw if required environment variables are not set.
  const tenderlyEnv = processEnvironment();

  // Get provider for the Tenderly fork.
  const tenderlyFork = await getTenderlyFork(forkId);
  const provider = new providers.StaticJsonRpcProvider(tenderlyFork.rpcUrl);

  // Validate address and balance.
  if (!utils.isAddress(address)) throw new Error(`Invalid address: ${address}`);
  if (!BigNumber.from(balance).gte(0))
    throw new Error(`Invalid balance: ${balance}`);

  // Send RPC request to set balance.
  await provider.send("tenderly_setBalance", [
    [address],
    utils.hexValue(BigNumber.from(balance).toHexString()),
  ]);

  // Changing balance updated the fork head, so we need to get the updated fork.
  const updatedFork = await getTenderlyFork(forkId);
  if (updatedFork.headId === undefined)
    throw new Error(`Failed to get updated fork head ID`);
  return updatedFork.headId;
};

export const findForkByDescription = async (
  description: string
): Promise<TenderlyForkResult | undefined> => {
  // Will throw if required environment variables are not set.
  const tenderlyEnv = processEnvironment();

  // Construct Tenderly fork API request.
  const url = `https://api.tenderly.co/api/v1/account/${tenderlyEnv.user}/project/${tenderlyEnv.project}/forks`;
  const headers = { "X-Access-Key": tenderlyEnv.apiKey };

  // Send Tenderly fork API request (Axios will throw if the HTTP response is not valid).
  const response = await axiosInstance.get(url, { headers });

  // If the HTTP response was valid, we expect the response body should be a JSON object containing expected Tenderly fork
  // response properties.
  if (
    typeof response.data !== "object" ||
    !Array.isArray(response.data.simulation_forks) ||
    !response.data.simulation_forks.every((simulationFork) =>
      isTenderlySimulationFork(simulationFork)
    )
  ) {
    throw new Error(
      `Failed to parse Tenderly fork API response: ${JSON.stringify(
        response.data
      )}`
    );
  }

  // Find the fork with the matching description.
  const matchingFork = response.data.simulation_forks.find(
    (simulationFork) => simulationFork.description === description
  );

  // If we found a matching fork, return the translated result.
  if (matchingFork !== undefined)
    return forkAPIResponseToResult({ simulation_fork: matchingFork });

  // Otherwise, return undefined.
  return undefined;
};

export const setForkSimulationDescription = async (
  forkId: string,
  simulationId: string,
  description: string
): Promise<void> => {
  // Will throw if required environment variables are not set.
  const tenderlyEnv = processEnvironment();

  // Construct Tenderly fork API request.
  const url = `https://api.tenderly.co/api/v1/account/${tenderlyEnv.user}/project/${tenderlyEnv.project}/fork/${forkId}/transaction/${simulationId}`;
  const body = { description };
  const headers = { "X-Access-Key": tenderlyEnv.apiKey };

  // Send Tenderly fork API request (Axios will throw if the HTTP response is not valid).
  await axiosInstance.put(url, body, { headers });
}
