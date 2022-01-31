
contract TestENS {
    mapping (bytes32 => address) owners;

    function setOwner(bytes32 nodehash, address owner) public {
        owners[nodehash] = owner;
    }

    function owner(bytes32 nodehash) public view returns (address) {
        return owners[nodehash];
    }
}
