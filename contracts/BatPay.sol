pragma solidity ^0.4.24;
import "./IERC20.sol";
import "./Merkle.sol";


contract BatPay {
    uint constant public maxAccount = 2**24-1;
    uint constant public maxBulk = 2**16;
    uint constant public newAccount = 2**256-1;
    uint constant public bytesPerId = 3;
    uint constant public maxBalance = 2**64-1;

    struct Account {
        address addr;
        uint64  balance;
        uint32  claimIndex;
    }

    struct Payment {
        bytes32 hash;
        uint64  amount;
        uint32  minId;
        uint32  maxId;
    }

    struct BulkRecord {
        bytes32 rootHash;
        uint64  n;
        uint64  minId;
    }

    address public owner;
    IERC20 public token;
    Account[] public accounts;
    BulkRecord[] public bulkRegistrations;
    Payment[] public payments;

    
    constructor(address _token) public {
        owner = msg.sender;
        token = IERC20(_token);
    }

    // Reserve n accounts but delay assigning addresses
    // Accounts will be claimed later using merkleTree's rootHash
    // Note: This should probably have some limitation to prevent
    //   DOS (maybe only owner?)

    function bulkRegister(uint256 n, bytes32 rootHash) public {
        require(n < maxBulk);
        require(accounts.length + n <= maxAccount);

        bulkRegistrations.push(BulkRecord(rootHash, uint64(n), uint64(accounts.length)));
        accounts.length += n;
    }


    // Register a new account

    function claimAddress(address addr, uint256[] proof, uint id, uint bulkId) public returns (bool) {
        require(bulkId < bulkRegistrations.length);
        uint minId = bulkRegistrations[bulkId].minId;
        uint n = bulkRegistrations[bulkId].n;
        bytes32 rootHash = bulkRegistrations[bulkId].rootHash;

        bytes32 hash = Merkle.evalProof(proof, id, uint256(addr));
        
        require(id >= minId && id < minId+n);
        require(hash == rootHash);

        accounts[id].addr = addr;
    }

    function register() public returns (uint32 ret) {
        require(accounts.length < maxAccount, "no more accounts left");
        ret = (uint32)(accounts.length);
        accounts.length += 1;
        accounts[ret] = Account(msg.sender, 0, 0);
    } 

    function withdraw(uint64 amount, uint256 id) public {
        require(id < accounts.length);
        
        address addr = accounts[id].addr;
        uint64 balance = accounts[id].balance;

        require(addr != 0);
        require(balance >= amount);
        require(amount > 0);

        require(msg.sender == addr);

        token.transfer(addr, amount);
        balance -= amount;
        
        accounts[id].balance = balance;
    }

    function deposit(uint64 amount, uint256 id) public {
        require(id < accounts.length || id == newAccount, "invalid id");
        require(amount > 0, "amount should be positive");
        require(token.transferFrom(msg.sender, address(this), amount), "transfer failed");

        if (id == newAccount)      
        {   // new account
            uint newId = register();
            accounts[newId].balance = amount;
        } else {  
            // existing account
            uint64 balance = accounts[id].balance;
            uint64 newBalance = balance + amount;

            // checking for overflow
            require(balance <= newBalance); 

            accounts[id].balance = newBalance;
       }
    }

    function transfer(uint id, uint64 amount, bytes payData, uint32 newCount, bytes32 roothash) public {
        require(id < accounts.length);
         
        address addr = accounts[id].addr;
        uint64 balance = accounts[id].balance;

        require(addr == msg.sender);
        require(payData.length % bytesPerId == 0);
        require(amount <= maxBalance);

        uint total = amount * (newCount + payData.length/4);
        
        require (total <= balance);
        accounts[id].balance = balance - uint64(total);

        uint32 minId = uint32(accounts.length);
        uint32 maxId = minId + newCount;
        require(maxId >= minId);
        
        if (newCount > 0) bulkRegister(newCount, roothash);

        bytes32 hash = keccak256(abi.encodePacked(payData));
        payments.push(Payment(hash, amount, minId, maxId));
    }



    function balanceOf(uint id) public view returns (uint64) {
        require(id < accounts.length);
        return accounts[id].balance;
    }

    function accountsLength() public view returns (uint) {
        return accounts.length;
    }

    function bulkLength() public view returns (uint) {
        return bulkRegistrations.length;
    }

}