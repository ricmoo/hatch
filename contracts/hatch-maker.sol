
// namehash("hatch.eth")
bytes32 constant nodehashHatch = 0x54e801acbb1a4f9d2f51dae289e38bc712f13d4dca03b5321203b74e9869a091;
bytes32 constant nodehashReverse = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;

// dnsEncode("hatch.eth")
string constant dnsHatch = "\x05hatch\x03eth\x00";


interface ReverseRegistrar {
    function setName(string memory name) external returns (bytes32);
}

interface Resolver {
    function addr(bytes32 nodehash) external view returns (address);
}

interface ResolverMulticoin {
    function addr(bytes32 nodehash, uint coinType) external view returns (address);
}

interface AbstractENS {
    function owner(bytes32 nodehash) external view returns (address);
    function resolver(bytes32) external view returns (address);
}


function _keccak(uint offset, uint length, bytes memory data) view returns (bytes32 result) {
    assembly {
        result := keccak256(add(offset, add(data, 32)), length)
    }
}

function _namehash(uint offset, bytes memory dnsName) view returns (bytes32) {
    require(offset < dnsName.length);

    uint8 length = uint8(dnsName[offset]);
    if (length == 0) { return 0; }

    uint start = offset + 1;
    uint end = start + length;

    return keccak256(abi.encodePacked(
        _namehash(end, dnsName),
        _keccak(start, length, dnsName)
    ));
}

function namehash(bytes memory dnsName) view returns (bytes32) {
    return _namehash(0, dnsName);
}


// A Nook is a permanent wallet deployed by a Proxy. It is counterfactually
// deployed, so its address can be used to store ether by a proxy, for
// example if the proxy self-destructs. At any point a Proxy may call reclaim
// to receive its ether back.
contract NookWallet {
    address payable public immutable owner;

    constructor() {
        owner = payable(msg.sender);
        reclaim();
    }

    // Forwards all funds in this Nook to its Proxy
    function reclaim() public {
        require(msg.sender == owner);
        owner.send(address(this).balance);
    }

    // Allow receiving funds
    receive() external payable { }
}

// The proxy is a smart contract wallet
contract Proxy {
    address public immutable ens;
    bytes32 public immutable nodehash;

    constructor(address _ens, bytes32 _nodehash) {
        ens = _ens;
        nodehash = _nodehash;
    }

    function nookAddress() public view returns (address payable nook) {
        return payable(address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            nodehash,
            keccak256(type(NookWallet).creationCode)
        ))))));
    }

    function reclaimNook() external returns (address) {
        address payable nook = nookAddress();

        if (nook.codehash == 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470) {
            // If the nook isn't deployed, deploy it (which forwards all funds to this)
            new NookWallet{ salt: nodehash }();
        } else {
            // Otherwise, call reclaim
            NookWallet(nook).reclaim();
        }

        return nook;
    }

    function execute(address target, bytes calldata data, uint value) public returns (bool status, bytes memory result) {
        // Owner the controller can call this
        require(AbstractENS(ens).owner(nodehash) == msg.sender, "not authorized");

        // We use assembly so we can call EOAs
        assembly {
            status := call(gas(), target, value, data.offset, data.length, 0, 0)
            result := mload(0x40)
            mstore(0x40, add(result, and(add(add(returndatasize(), 0x20), 0x1f), not(0x1f))))
            mstore(result, returndatasize())
            returndatacopy(add(result, 32), 0, returndatasize())
        }
    }

    function executeMulitple(address[] calldata targets, bytes[] calldata datas, uint[] calldata values) external returns (bool[] memory statuses, bytes[] memory results) {
        require(targets.length == datas.length);
        require(targets.length == values.length);

        statuses = new bool[](targets.length);
        results = new bytes[](targets.length);

        for (uint i = 0; i < targets.length; i++) {
            (bool status, bytes memory result) = execute(targets[i], datas[i], values[i]);
            statuses[i] = status;
            results[i] = result;
        }
    }

    function remove() external {
        // Owner the controller can call this
        require(AbstractENS(ens).owner(nodehash) == msg.sender, "not authorized");

        // Send all funds (at the conclusion of this tx) to the nook
        // address, which can be counter-factually deployed later
        selfdestruct(nookAddress());
    }

    // Allow receiving funds
    receive() external payable { }
}

contract HatchMaker {

    address immutable ens;

    event DeployedProxy(bytes indexed indexedName, bytes dnsName, address owner);

    constructor(address _ens) {
        ens = _ens;

        // Set the reverse record
        address reverseRegistrar = AbstractENS(ens).owner(nodehashReverse);
        ReverseRegistrar(reverseRegistrar).setName("hatch.eth");
    }

    function _addressForNodehash(bytes32 nodehash) internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            nodehash,
            keccak256(abi.encodePacked(
              type(Proxy).creationCode,
              bytes32(uint(uint160(ens))),
              nodehash
            ))
        )))));
    }

    function addressForName(bytes calldata dnsName) public view returns (address) {
        return _addressForNodehash(namehash(dnsName));
    }

    function deployProxy(bytes calldata dnsName) external returns (address) {
        bytes32 nodehash = namehash(dnsName);
        Proxy proxy = new Proxy{ salt: nodehash }(ens, nodehash);
        emit DeployedProxy(dnsName, dnsName, address(proxy));
        return address(proxy);
    }

    // Returns the Proxy for addr calls, and forwards all other requests
    // to the name's resolver
    function resolve(bytes calldata dnsName, bytes calldata data) external view returns (bytes memory) {
        bytes4 sel = bytes4(data[0:4]);

        // Handle the hatch.eth root
        if (keccak256(dnsName) == keccak256(bytes(dnsHatch)) && data.length >= 36) {

            // [ bytes4:selector ][ bytes32:namehash("hatch.eth") ]
            require(bytes32(data[4:36]) == nodehashHatch);

            // [ bytes4:selectoraddr(bytes32) ][ bytes32:namehash("hatch.eth") ]
            if (data.length == 36 && sel == Resolver.addr.selector) {
                return abi.encode(address(this));
            }

            // [ bytes4:selectoraddr(bytes32) ][ bytes32:namehash("hatch.eth") ][ uint:60 ]
            if (data.length == 68 && sel == ResolverMulticoin.addr.selector) {
                if (uint(bytes32(data[36:68])) == 60) {
                    return abi.encode(abi.encodePacked(address(this)));
                }
            }

            // @TODO: Handle fun things like avatar
            revert("todo");

            //address resolver = ens.resolver(??);
            //require(resolver != address(0));

            //return resolver.call(abi.encodePacked(data[0:4], ownerNodehash, data[36:]));
        }

        // Length of the hatch owner label
        uint length = uint8(dnsName[0]);

        // Must match XXX.hatch.eth
        require(keccak256(dnsName[1 + length:]) == keccak256(bytes(dnsHatch)), "unknown suffix");

        // The hatch owner name and hash (e.g. ricmoo.hatch.eth => ricmoo.eth)
        bytes memory ownerName = abi.encodePacked(dnsName[0: length + 1], "\x03eth\x00");
        bytes32 ownerNodehash = namehash(ownerName);

        // Hijack: addr(bytes32 nodehash) view returns (address)
        // Returns the hatch address instead of returning the
        // target resolver's address. [EIP-]
        if (data.length == 36 && sel == Resolver.addr.selector) {
            //require(namehash(dnsName) == bytes32(data[4:36]));
            return abi.encode(_addressForNodehash(ownerNodehash));
        }

        // Hijack: addr(bytes32 nodehash, uint cointype) view returns (address)
        // Returns the hatch address instead of returning the
        // target resolver's address. [EIP-]
        if (data.length == 68 && sel == ResolverMulticoin.addr.selector && uint(bytes32(data[36:68])) == 60) {
            //require(namehash(dnsName) == bytes32(data[4:36]));
            return abi.encode(abi.encodePacked(_addressForNodehash(ownerNodehash)));
        }

        // Forward the request to the actual resolver, replacing the nodehash
        // with the owner nodehash
        address resolver = AbstractENS(ens).resolver(ownerNodehash);
        require(resolver != address(0));

        // @TODO: Check for wildcard support and use resolve(bytes, bytes) instead

        (bool status, bytes memory result) = resolver.staticcall(abi.encodePacked(data[0:4], ownerNodehash, data[36:]));

        if (status) { revert("call reverted"); }

        return result;
    }
}
