// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IPyth} from "../../src/interfaces/pyth/IPyth.sol";

contract MockPyth is IPyth {
    int64 public price;
    uint64 public conf;
    int32 public expo;
    uint256 public publishTime;

    function setLatestPrice(int64 _price, uint64 _conf, int32 _expo, uint256 _publishTime) public {
        price = _price;
        conf = _conf;
        expo = _expo;
        publishTime = _publishTime;
    }

    function getPrice(bytes32 id) external view returns (IPyth.Price memory) {
        return getPriceUnsafe(id);
    }

    function getPriceUnsafe(bytes32 /* id */ ) public view returns (IPyth.Price memory) {
        return IPyth.Price({price: price, conf: conf, expo: expo, publishTime: publishTime});
    }
}
