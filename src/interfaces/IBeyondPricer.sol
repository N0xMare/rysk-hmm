pragma solidity ^0.8.19;

import "../libraries/Types.sol";

interface IBeyondPricer {
    function quoteOptionPrice(
		Types.OptionSeries memory _optionSeries,
		uint256 _amount,
		bool isSell,
		int256 netDhvExposure
	) external returns (uint256 totalPremium, int256 totalDelta, uint256 totalFees);
}