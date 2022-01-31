
bytes32 constant NH_ = bytes32(0);

bytes32 constant NH_REVERSE = 0xa097f6721ce401e757d1223a763fef49b8b5f90bb18567ddb86fd205dff71d34;
bytes32 constant NH_REVERSE_ADDR = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;

bytes32 constant NH_ETH = 0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae;
bytes32 constant NH_ETH_RESOLVER = 0xfdd5d5de6dd63db72bbc2d487944ba13bf775b50a80805fe6fcaba9b0fba88f5;



function sha3HexAddress(address addr) pure returns (bytes32 ret) {
    assembly {
        let lookup := 0x3031323334353637383961626364656600000000000000000000000000000000

        for { let i := 40 } gt(i, 0) { } {
            i := sub(i, 1)
            mstore8(i, byte(and(addr, 0xf), lookup))
            addr := div(addr, 0x10)
            i := sub(i, 1)
            mstore8(i, byte(and(addr, 0xf), lookup))
            addr := div(addr, 0x10)
        }

        ret := keccak256(0, 40)
    }
}

contract ReverseRegistrar {

    ENS immutable _ens;
    Resolver immutable _resolver;

    constructor(ENS ens) {
        _ens = ens;
        _resolver = new Resolver(ens, address(this));
    }

    function claimWithResolver(address owner, address resolver) public returns (bytes32) {
        bytes32 labelhash = sha3HexAddress(msg.sender);
        bytes32 nodehash = keccak256(abi.encodePacked(NH_REVERSE_ADDR, labelhash));
        address currentOwner = _ens.owner(nodehash);

        // Update the resolver if required
        if (resolver != address(0x0) && resolver != _ens.resolver(nodehash)) {
            // Transfer the name to us first if it's not already
            if (currentOwner != address(this)) {
                _ens.setSubnodeOwner(NH_REVERSE_ADDR, labelhash, address(this));
                currentOwner = address(this);
            }
            _ens.setResolver(nodehash, resolver);
        }

        // Update the owner if required
        if (currentOwner != owner) {
            _ens.setSubnodeOwner(NH_REVERSE_ADDR, labelhash, owner);
        }

        return nodehash;
    }

    function setName(string memory name) external returns (bytes32) {
        bytes32 node = claimWithResolver(address(this), address(_resolver));
        _resolver.setName(node, name);
        return node;
    }

}
/*
contract EthRegistrar {
    ENS immutable _ens;

    constructor(ENS ens) {
        _ens = ens;
    }

    function register(bytes32 labelhash, address owner) external returns (bytes32) {
        bytes32 nodehash = keccak256(abi.encodePacked(NH_ETH, labelhash));
        require(_ens.owner(nodehash) == address(0));
        _ens.setSubnodeOwner(NH_ETH, labelhash, owner);
        return nodehash;
    }
}
*/
contract Resolver {

    struct Record {
        address addr;
        string name;
    }

    mapping (bytes32 => Record) _data;

    ENS immutable _ens;

    constructor(ENS ens, address reverseResolver) {
        _ens = ens;

        // Configure .eth to point to the ENS registry/registrar
        _data[NH_ETH].addr = address(ens);

        // Configure resolver.eth to point to this
        _data[NH_ETH_RESOLVER].addr = address(this);

        // Configure addr.reverse (this will be ignored except by the resolver
        // deployed by the ENS contract)
        _data[NH_REVERSE_ADDR].addr = reverseResolver;
    }


    function setName(bytes32 nodehash, string calldata name) external {
        require(_ens.owner(nodehash) == msg.sender);
        _data[nodehash].name = name;
    }

    function name(bytes32 nodehash) external view returns (string memory) {
        return _data[nodehash].name;
    }


    function setAddr(bytes32 nodehash, address addr) external {
        require(_ens.owner(nodehash) == msg.sender);
        _data[nodehash].addr = addr;
    }

    function addr(bytes32 nodehash) external view returns (address) {
        return _data[nodehash].addr;
    }
}

// This test ENS Registry is also the registrar.
contract ENS {

    struct Record {
        address owner;
        address resolver;
    }

    mapping (bytes32 => Record) _data;

    Resolver immutable _resolver;


    constructor() {
        _data[NH_].owner = address(this);

        ReverseRegistrar reverseRegistrar = new ReverseRegistrar(this);
        _resolver = new Resolver(this, address(reverseRegistrar));

        // Configure the .eth registrar and point `eth` to this address
        _data[NH_ETH].owner = address(this);
        _data[NH_ETH].resolver = address(_resolver);

        // Configure resolver.eth to point to a default resolver
        _data[NH_ETH_RESOLVER].owner = address(this);
        _data[NH_ETH_RESOLVER].resolver = address(_resolver);

        // Configure the reverse registrar
        _data[NH_REVERSE_ADDR].owner = address(reverseRegistrar);
        _data[NH_REVERSE_ADDR].resolver = address(_resolver);
    }


    function setSubnodeOwner(bytes32 nodehash, bytes32 labelhash, address owner) external returns (bytes32) {
        require(msg.sender == _data[nodehash].owner);
        bytes32 subnodehash = keccak256(abi.encodePacked(nodehash, labelhash));
        _data[subnodehash].owner = owner;
        return subnodehash;
    }


    function setOwner(bytes32 nodehash, address owner) external {
        require(_data[nodehash].owner == msg.sender);
        _data[nodehash].owner = owner;
    }

    function owner(bytes32 nodehash) external view returns (address) {
        return _data[nodehash].owner;
    }


    function setResolver(bytes32 nodehash, address resolver) external {
        require(_data[nodehash].owner == msg.sender);
        _data[nodehash].resolver = resolver;
    }

    function resolver(bytes32 nodehash) external view returns (address) {
        return _data[nodehash].resolver;
    }

    function resolver() external view returns (address) {
        return address(_resolver);
    }

    function register(bytes32 labelhash, address owner) external returns (bytes32) {
        bytes32 subnodehash = keccak256(abi.encodePacked(NH_ETH, labelhash));
        require(_data[subnodehash].owner == address(0));

        _data[subnodehash].owner = address(this);
        _data[subnodehash].resolver = address(_resolver);
        _resolver.setAddr(subnodehash, owner);
        _data[subnodehash].owner = owner;

        return subnodehash;
    }

}
