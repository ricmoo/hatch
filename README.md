Hatch.eth
=========

The HatchMaker is a smart contract which can instill life (i.e. deploy)
into a Wisp, which is bound to the owner of a top-level ENS name.

Each Wisp is a smart contract wallet, which can be deployed, removed and
then re-deployed to the blockchain any number of times. The Wisp can
execute any operation, so it can manage ether, NFTs, ERC-20 tokens or
anything else, including atomically executing a series of transactions.

For any top-level ENS name, such as ricmoo.eth, the Wisp will be deployed
at ricmoo.hatch.eth, which means any assets may be sent to that address and
remain under the control of the corresponding top-level ENS name.

Assets may be sent to the Wisp at any time, even before a name is owned,
although this is a bad idea, since then anyone could register the name
and gain control over those assets. Assets can also be sent to a name that
seems to be unattended and only the owner of that name will be able to
access them.

If a Wisp is ordered to self-destruct any ether is moved into a secure
nook, which can be reclaimed in the future, once the Wisp has been brought
back to life.


API
---

```javascript
const hatchMaker = new Contract("hatch.eth", [
    "function addressForName(bytes dnsName) view returns (address)",
    "function deployProxy(bytes dnsName) view returns (address)"
], signer);

const wisp = new Contact("ricmoo.hatch.eth", [
    "function nookAddress() returns (address)",
    "function reclaimNook() returns (address)",
    "function execute(address target, bytes data, uint value) returns (bool, bytes)",
    "function executeMultiple(address[] target, bytes[] data, uint[] value) returns (bool[], bytes[])",
    "function remove()"
], signer);
```


Why do this?
------------

This is mainly a little toy example of the power of wildcard ENS names and
a test for ethers that resolution works.

Also, it's a fund example.


License
-------

MIT License.
