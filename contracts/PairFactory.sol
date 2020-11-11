pragma solidity 0.5.12;

import "./Pair.sol";

contract PairFactory {
    address private _controller;

    mapping(address => address) private _hasPair;

    constructor() public {
        _controller = msg.sender;
    }

    function newPair(address pool, uint256 perBlock, uint256 rate)
    external
    returns (PairToken pair)
    {
        require(_hasPair[address(pool)] == address(0), "ERR_ALREADY_HAS_PAIR");

        pair = new PairToken(pool, perBlock, rate);
        _hasPair[address(pool)] = address(pair);

        pair.setController(msg.sender);
        return pair;
    }


    function getPairToken(address pool)
    external view
    returns (address)
    {
        return _hasPair[pool];
    }
}