
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PolyToken is ERC20 {
    address public owner;

    constructor() ERC20("Poly Token", "POLY") {
        owner = msg.sender;
        
        _mint(msg.sender, 100000 * 10**decimals());
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "Only owner can mint");
        _mint(to, amount);
    }
}