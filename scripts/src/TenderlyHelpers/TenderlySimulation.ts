// Simulates transaction results on Tenderly.
// Requires environment variables TENDERLY_USER, TENDERLY_PROJECT and TENDERLY_ACCESS_KEY to be set, check:
// - https://docs.tenderly.co/other/platform-access/how-to-find-the-project-slug-username-and-organization-name
// - https://docs.tenderly.co/other/platform-access/how-to-generate-api-access-tokens

import axios from "axios";
import { BigNumber, constants, utils } from "ethers";
import * as dotenv from "dotenv";

const axiosInstance = axios.create({
  validateStatus: (status) => status >= 200 && status < 300,
});

export interface TenderlyEnvironment {
  user: string;
  project: string;
  apiKey: string;
}

interface ForkParams {
  id: string;
  root?: string; // If provided, simulation will be performed on top of this earlier simulation id.
}

// Simulation parameters passed by the caller.
export interface TenderlySimulationParams {
  chainId: number;
  to?: string;
  input?: string;
  value?: string;
  from?: string; // If not provided, the zero address is used in the simulation.
  timestampOverride?: number;
  fork?: ForkParams;
  description?: string;
}

interface ResultUrl {
  url: string; // This is the URL to the simulation result page (public or private).
  public: boolean; // This is false if the project is not publicly accessible.
}

// Simulation properties returned to the caller.
export interface TenderlySimulationResult {
  id: string;
  status: boolean; // True if the simulation succeeded, false if it reverted.
  gasUsed: number;
  resultUrl: ResultUrl;
}

// We only type Tenderly simulation API request properties that we use.
interface TenderlyRequestBody {
  save: boolean;
  save_if_fails: boolean;
  simulation_type: "quick" | "abi" | "full";
  network_id: string;
  from: string;
  to?: string;
  input?: string;
  value?: string;
  root?: string;
  block_header?: {
    timestamp: string;
  };
  description?: string;
}

// We only type Tenderly simulation API response properties that we use.
interface TenderlyAPIResponse {
  simulation: {
    id: string;
    status: boolean;
    receipt: { gasUsed: string };
  };
}

export const processEnvironment = (): TenderlyEnvironment => {
  dotenv.config();

  if (!process.env.TENDERLY_USER) throw new Error("TENDERLY_USER not set");
  if (!process.env.TENDERLY_PROJECT)
    throw new Error("TENDERLY_PROJECT not set");
  if (!process.env.TENDERLY_ACCESS_KEY)
    throw new Error("TENDERLY_ACCESS_KEY not set");

  return {
    user: process.env.TENDERLY_USER,
    project: process.env.TENDERLY_PROJECT,
    apiKey: process.env.TENDERLY_ACCESS_KEY,
  };
};

const validateSimulationParams = (
  simulationParams: TenderlySimulationParams
): void => {
  if (simulationParams.to !== undefined && !utils.isAddress(simulationParams.to))
    throw new Error(`Invalid to address: ${simulationParams.to}`);
  if (simulationParams.from !== undefined && !utils.isAddress(simulationParams.from))
    throw new Error(`Invalid from address: ${simulationParams.from}`);
  if (
    simulationParams.input !== undefined &&
    !utils.isBytesLike(simulationParams.input)
  )
    throw new Error(`Invalid input: ${simulationParams.input}`);
  if (
    simulationParams.value !== undefined &&
    !BigNumber.from(simulationParams.value).gte(0)
  )
    throw new Error(`Invalid value: ${simulationParams.value}`);
  if (
    simulationParams.timestampOverride !== undefined &&
    !BigNumber.from(simulationParams.timestampOverride).gte(0)
  )
    throw new Error(
      `Invalid timestampOverride: ${simulationParams.timestampOverride}`
    );
};

const createRequestUrl = (
  tenderlyEnv: TenderlyEnvironment,
  fork?: ForkParams
): string => {
  const baseUrl = `https://api.tenderly.co/api/v1/account/${tenderlyEnv.user}/project/${tenderlyEnv.project}/`;
  return fork === undefined
    ? baseUrl + "simulate"
    : baseUrl + "fork/" + fork.id + "/simulate";
};

const createRequestBody = (
  simulationParams: TenderlySimulationParams
): TenderlyRequestBody => {
  const body: TenderlyRequestBody = {
    save: true,
    save_if_fails: true,
    simulation_type: "full",
    network_id: simulationParams.chainId.toString(),
    to: simulationParams.to,
    input: simulationParams.input,
    value: simulationParams.value,
    from: simulationParams.from || constants.AddressZero,
    root: simulationParams.fork?.root,
    description: simulationParams.description,
  };

  if (simulationParams.timestampOverride !== undefined) {
    body.block_header = {
      timestamp: BigNumber.from(
        simulationParams.timestampOverride
      ).toHexString(),
    };
  }

  return body;
};

// Type guard function to check if the API response conforms to the required TenderlyAPIResponse interface
function isTenderlyAPIResponse(response: any): response is TenderlyAPIResponse {
  if (
    response &&
    response.simulation &&
    typeof response.simulation.id === "string" &&
    typeof response.simulation.status === "boolean" &&
    response.simulation.receipt &&
    typeof response.simulation.receipt.gasUsed === "string"
  ) {
    return true;
  }
  return false;
}

const getSimulationResponse = async (
  simulationParams: TenderlySimulationParams,
  tenderlyEnv: TenderlyEnvironment,
): Promise<TenderlyAPIResponse> => {
  // Construct Tenderly simulation API request.
  const url = createRequestUrl(tenderlyEnv, simulationParams.fork);
  const body = createRequestBody(simulationParams);
  const headers = { "X-Access-Key": tenderlyEnv.apiKey };

  // Send Tenderly simulation API request (Axios will throw if the HTTP response is not valid).
  const response = await axiosInstance.post(url, body, { headers });

  // If the HTTP response was valid, we expect the response body should be a JSON object containing expected Tenderly
  // simulation response properties.
  if (!isTenderlyAPIResponse(response.data)) {
    throw new Error(
      `Failed to parse Tenderly simulation API response: ${JSON.stringify(
        response.data
      )}`
    );
  }
  return response.data;
};

const isProjectPublic = async (
  tenderlyEnv: TenderlyEnvironment,
): Promise<boolean> => {
  const url = `https://api.tenderly.co/api/v1/public/account/${tenderlyEnv.user}/project/${tenderlyEnv.project}`;
  const headers = { "X-Access-Key": tenderlyEnv.apiKey };

  // Return true only if the project API responds OK and the project is public. On any error, return false.
  try {
    const response = await axiosInstance.get(url, { headers });
    const projectResponse = response.data as {
      project: { public: boolean };
    };
    return projectResponse.project.public;
  } catch {
    return false;
  }
};

const getResultUrl = async (
  simulationId: string,
  tenderlyEnv: TenderlyEnvironment,
  fork?: ForkParams
): Promise<ResultUrl> => {
  const publicUrl = `https://dashboard.tenderly.co/public/${tenderlyEnv.user}/${
    tenderlyEnv.project
  }/${fork !== undefined ? "fork-simulation" : "simulator"}/${simulationId}`;
  const privateUrl = `https://dashboard.tenderly.co/${tenderlyEnv.user}/${
    tenderlyEnv.project
  }/${
    fork !== undefined ? "fork/" + fork.id + "/simulation" : "simulator"
  }/${simulationId}`;

  return (await isProjectPublic(tenderlyEnv))
    ? { url: publicUrl, public: true }
    : { url: privateUrl, public: false };
};

export const simulateTenderlyTx = async (
  simulationParams: TenderlySimulationParams,
): Promise<TenderlySimulationResult> => {
  // Will throw if required environment variables are not set.
  const tenderlyEnv = processEnvironment();

  // Will throw if simulation parameters are invalid.
  validateSimulationParams(simulationParams);

  // Will throw if Tenderly API request fails or returns unparsable response.
  const simulationResponse = await getSimulationResponse(
    simulationParams,
    tenderlyEnv,
  );

  // Get the URL to the simulation result page. If project is not public, the URL will be private (requires login).
  const resultUrl = await getResultUrl(
    simulationResponse.simulation.id,
    tenderlyEnv,
    simulationParams.fork
  );

  return {
    id: simulationResponse.simulation.id,
    status: simulationResponse.simulation.status,
    gasUsed: parseInt(simulationResponse.simulation.receipt.gasUsed),
    resultUrl,
  };
};
