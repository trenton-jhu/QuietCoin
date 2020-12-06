pragma solidity ^0.7.0;
// SPDX-License-Identifier: JHU

contract QuietCoin {
    struct Volunteer {
        bool registered;
        uint amount;
        uint locked_amount;
    }

    struct User {
        uint balance;
        address assignee;
    }

    struct Order {
        address payable user;
        address volunteer;
        uint usd_amount;
        uint time_created;
    }
    
    mapping (address => User) public users;
    uint public usd_to_wei; // how much weis 1 USD can buy
    uint public bid_price;
    uint public ask_price;
    uint public collateral_rate;
    mapping (address => Volunteer) public volunteers;
    address[] public volunteer_addr;
    Order[] public orders;
    uint[] public votes;
    uint public vote_index;
    uint public look_back_period;

    constructor() {
        // TODO: Properly initiate conversion rate values
        usd_to_wei = 10000000000000;
        collateral_rate = 4;
        bid_price = 99;
        ask_price = 101;
        look_back_period = 25;
        for (uint i = 0; i < look_back_period; i++) {
            votes.push(usd_to_wei);
        }
    }

    // Register with ETH to be a volunteer
    function register() public payable {
        if (volunteers[msg.sender].registered) {
            volunteers[msg.sender].amount += msg.value;
        } else {
            volunteers[msg.sender].registered = true;
            volunteers[msg.sender].amount = msg.value;
            volunteer_addr.push(msg.sender);
        }
    }

    // Take away ETH from your volunteered amount
    function deregister(uint amount) public {
        require(volunteers[msg.sender].registered, "Not a valid volunteer");
        require(
            amount <= volunteers[msg.sender].amount - volunteers[msg.sender].locked_amount,
            "Insufficient freed amount to withdraw"
        );
        volunteers[msg.sender].amount -= amount;
        msg.sender.transfer(amount);
    }
    
    // User deposity usd, which will be kept at stable price
    function deposit(uint n_usd) public payable returns (address v) {
        require(volunteer_addr.length > 0, "No volunteers present");
        uint wei_needed = n_usd * bid_price * usd_to_wei / 100;
        require(msg.value > wei_needed, "Insufficient ether to back deposit USD amount");

        // If previously assinged volunteer
        address addr = users[msg.sender].assignee;
        if (addr != address(0)) {
            if (volunteers[addr].amount - volunteers[addr].locked_amount >= collateral_rate * wei_needed) {
                volunteers[addr].locked_amount += collateral_rate * wei_needed;
                users[msg.sender].balance += n_usd;
                return addr;
            } else {
                revert("Your assigned volunteer cannot back more amount");
            }
        }
        
        // Find and assign volunteer
        for (uint i = 0; i < volunteer_addr.length; i++) {
            address v_addr = volunteer_addr[i];
            if (volunteers[v_addr].amount - volunteers[v_addr].locked_amount >= collateral_rate * wei_needed) {
                volunteers[v_addr].locked_amount += collateral_rate * wei_needed;
                users[msg.sender].balance += n_usd;
                users[msg.sender].assignee = addr;
                return addr;
            }
        }

        // Transfer change back to user
        msg.sender.transfer(msg.value - wei_needed);
        
        // No volunteer found
        revert("No volunteer found");
    }

    // User request a withdrawal for the usd they deposited
    function requestWithdrawal(uint n_usd) public returns (uint order_id) {
        require(users[msg.sender].balance >= n_usd, "Insufficient USD amount to withdraw");
        orders.push(Order({
            user: msg.sender,
            volunteer: users[msg.sender].assignee,
            usd_amount: n_usd,
            time_created: block.number
        }));
        return orders.length - 1;
    }

    // Volunteer fulfill a withdrawl request identified by order_id made by the user 
    function fulfillWithdrawal(uint order_id) public payable {
        require(order_id < orders.length, "No such cash out order exists");
        require(orders[order_id].volunteer == msg.sender, "Wrong user to cash out");
        require(msg.value > orders[order_id].usd_amount * ask_price * usd_to_wei / 100, "Insufficient ether to cash out this USD amount");

        users[orders[order_id].user].balance -= orders[order_id].usd_amount;
        orders[order_id].user.transfer(orders[order_id].usd_amount * ask_price * usd_to_wei / 100);
        
        msg.sender.transfer(msg.value - orders[order_id].usd_amount * ask_price * usd_to_wei / 100);
        delete orders[order_id];
    }

    // Vote on the conversion rate
    function vote(uint usd_to_wei_vote) public {
        uint prev_vote = votes[vote_index];
        votes[vote_index] = usd_to_wei_vote;
        vote_index += 1;
        vote_index %= look_back_period;
        usd_to_wei = (usd_to_wei * look_back_period - prev_vote + usd_to_wei_vote) / look_back_period; 
    }
}
