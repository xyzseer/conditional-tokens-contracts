pragma solidity 0.4.11;
import "Markets/AbstractMarket.sol";
import "Tokens/AbstractToken.sol";
import "Events/AbstractEvent.sol";
import "MarketMakers/AbstractMarketMaker.sol";


/// @title Market factory contract - Allows to create market contracts
/// @author Stefan George - <stefan@gnosis.pm>
contract DefaultMarket is Market {
    using Math for *;

    /*
     *  Constants
     */
    uint public constant FEE_RANGE = 1000000; // 100%

    /*
     *  Storage
     */
    address public creator;
    uint public createdAtBlock;
    Event public eventContract;
    MarketMaker public marketMaker;
    uint public fee;
    uint public funding;
    int[] public netOutcomeTokensSold;

    /*
     *  Modifiers
     */
    modifier isCreator () {
        // Only creator is allowed to proceed
        require(msg.sender == creator);
        _;
    }

    /*
     *  Public functions
     */
    /// @dev Constructor validates and sets market properties
    /// @param _creator Market creator
    /// @param _eventContract Event contract
    /// @param _marketMaker Market maker contract
    /// @param _fee Market fee
    function DefaultMarket(address _creator, Event _eventContract, MarketMaker _marketMaker, uint _fee)
        public
    {
        // Validate inputs
        require(address(_eventContract) != 0 && address(_marketMaker) != 0 && _fee < FEE_RANGE);
        creator = _creator;
        createdAtBlock = block.number;
        eventContract = _eventContract;
        netOutcomeTokensSold = new int[](eventContract.getOutcomeCount());
        fee = _fee;
        marketMaker = _marketMaker;
    }

    /// @dev Allows to fund the market with collateral tokens converting them into outcome tokens
    /// @param _funding Funding amount
    function fund(uint _funding)
        public
        isCreator
    {
        // Request collateral tokens and allow event contract to transfer them to buy all outcomes
        require(   eventContract.collateralToken().transferFrom(msg.sender, this, _funding)
                && eventContract.collateralToken().approve(eventContract, _funding));
        eventContract.buyAllOutcomes(_funding);
        funding = funding.add(_funding);
    }

    /// @dev Allows market creator to close the markets by transferring all remaining outcome tokens to the creator
    function close()
        public
        isCreator
    {
        uint8 outcomeCount = eventContract.getOutcomeCount();
        for (uint8 i=0; i<outcomeCount; i++)
            require(eventContract.outcomeTokens(i).transfer(creator, eventContract.outcomeTokens(i).balanceOf(this)));
    }

    /// @dev Allows market creator to withdraw fees generated by trades
    /// @return Returns fee amount
    function withdrawFees()
        public
        isCreator
        returns (uint fees)
    {
        fees = eventContract.collateralToken().balanceOf(this);
        // Transfer fees
        require(eventContract.collateralToken().transfer(creator, fees));
    }

    /// @dev Allows to buy outcome tokens from market maker
    /// @param outcomeTokenIndex Index of the outcome token to buy
    /// @param outcomeTokenCount Amount of outcome tokens to buy
    /// @param maxCost The maximum cost in collateral tokens to pay for outcome tokens
    /// @return Returns cost in collateral tokens
    function buy(uint8 outcomeTokenIndex, uint outcomeTokenCount, uint maxCost)
        public
        returns (uint cost)
    {
        // Calculate cost to buy outcome tokens
        uint outcomeTokenCost = marketMaker.calcCost(this, outcomeTokenIndex, outcomeTokenCount);
        // Calculate fee charged by market
        uint fee = calcMarketFee(outcomeTokenCost);
        cost = outcomeTokenCost.add(fee);
        // Check cost doesn't exceed max cost
        require(cost > 0 && cost <= maxCost);
        // Transfer tokens to markets contract and buy all outcomes
        require(   eventContract.collateralToken().transferFrom(msg.sender, this, cost)
                && eventContract.collateralToken().approve(eventContract, outcomeTokenCost));
        // Buy all outcomes
        eventContract.buyAllOutcomes(outcomeTokenCost);
        // Transfer outcome tokens to buyer
        require(eventContract.outcomeTokens(outcomeTokenIndex).transfer(msg.sender, outcomeTokenCount));

        require(int(outcomeTokenCount) >= 0);
        netOutcomeTokensSold[outcomeTokenIndex] = netOutcomeTokensSold[outcomeTokenIndex].add(int(outcomeTokenCount));
    }

    /// @dev Allows to sell outcome tokens to market maker
    /// @param outcomeTokenIndex Index of the outcome token to sell
    /// @param outcomeTokenCount Amount of outcome tokens to sell
    /// @param minProfit The minimum profit in collateral tokens to earn for outcome tokens
    /// @return Returns profit in collateral tokens
    function sell(uint8 outcomeTokenIndex, uint outcomeTokenCount, uint minProfit)
        public
        returns (uint profit)
    {
        // Calculate profit for selling outcome tokens
        uint outcomeTokenProfit = marketMaker.calcProfit(this, outcomeTokenIndex, outcomeTokenCount);
        // Calculate fee charged by market
        uint fee = calcMarketFee(outcomeTokenProfit);
        profit = outcomeTokenProfit.sub(fee);
        // Check profit is not too low
        require(profit > 0 && profit >= minProfit);
        // Transfer outcome tokens to markets contract to sell all outcomes
        require(eventContract.outcomeTokens(outcomeTokenIndex).transferFrom(msg.sender, this, outcomeTokenCount));
        // Sell all outcomes
        eventContract.sellAllOutcomes(outcomeTokenProfit);
        // Transfer profit to seller
        require(eventContract.collateralToken().transfer(msg.sender, profit));

        require(int(outcomeTokenCount) >= 0);
        netOutcomeTokensSold[outcomeTokenIndex] = netOutcomeTokensSold[outcomeTokenIndex].sub(int(outcomeTokenCount));
    }

    /// @dev Buys all outcomes, then sells all shares of selected outcome which were bought, keeping
    ///      shares of all other outcome tokens.
    /// @param outcomeTokenIndex Index of the outcome token to short sell
    /// @param outcomeTokenCount Amount of outcome tokens to short sell
    /// @param minProfit The minimum profit in collateral tokens to earn for short sold outcome tokens
    /// @return Returns cost to short sell outcome in collateral tokens
    function shortSell(uint8 outcomeTokenIndex, uint outcomeTokenCount, uint minProfit)
        public
        returns (uint cost)
    {
        // Buy all outcomes
        require(   eventContract.collateralToken().transferFrom(msg.sender, this, outcomeTokenCount)
                && eventContract.collateralToken().approve(eventContract, outcomeTokenCount));
        eventContract.buyAllOutcomes(outcomeTokenCount);
        // Short sell selected outcome
        eventContract.outcomeTokens(outcomeTokenIndex).approve(this, outcomeTokenCount);
        uint profit = this.sell(outcomeTokenIndex, outcomeTokenCount, minProfit);
        cost = outcomeTokenCount - profit;
        // Transfer outcome tokens to buyer
        uint8 outcomeCount = eventContract.getOutcomeCount();
        for (uint8 i =0; i<outcomeCount; i++)
            if (i != outcomeTokenIndex)
                require(eventContract.outcomeTokens(i).transfer(msg.sender, outcomeTokenCount));
        // Send change back to buyer
        require(eventContract.collateralToken().transfer(msg.sender, profit));
    }

    /// @dev Calculates fee to be paid to market maker
    /// @param outcomeTokenCost Cost for buying outcome tokens
    /// @return Returns fee for trade
    function calcMarketFee(uint outcomeTokenCost)
        public
        constant
        returns (uint)
    {
        return outcomeTokenCost * fee / FEE_RANGE;
    }
}
