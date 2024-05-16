pragma solidity 0.8.17;

interface IOSM {
    // function wards(address) external view returns (uint256); // Auth addresses
    // function rely(address usr) external; // Add auth (auth)
    // function deny(address usr) external; // Remove auth (auth)

    // function stopped() external view returns (uint256); // Determines if OSM can be poked.

    // function src() external view returns (address); // Address of source oracle.

    // function hop() external view returns (uint16); // Oracle delay in seconds.
    function zzz() external view returns (uint64); // Time of last update (rounded down to nearest multiple of hop).

    // function bud(address _addr) external view returns (uint256); // Whitelisted contracts, set by an auth

    // function stop() external; // Stop Oracle updates (auth)
    // function start() external; // Resume Oracle updates (auth)

    // function change(address src_) external; // Change source oracle (auth)
    // function step(uint16 ts) external; // Change hop (auth)

    // function void() external; // Reset price feed to invalid and stop updates (auth)

    // function pass() external view returns (bool); // Check if oracle update period has passed.
    // function poke() external; // Poke OSM for a new price (can be called by anyone)

    function peek() external view returns (bytes32, bool); // Return current price and if valid (whitelisted)
    // function peep() external view returns (bytes32, bool); // Return the next price and if valid (whitelisted)
    function read() external view returns (bytes32); // Return current price, only if valid (whitelisted)

    // function kiss(address a) external; // Add address to whitelist (auth)
    // function diss(address a) external; // Remove address from whitelist (auth)
    // function kiss(address[] calldata a) external; // Add addresses to whitelist (auth)
    // function diss(address[] calldata a) external; // Remove addresses from whitelist (auth)
}
