// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../libraries/Types.sol";

interface IAlphaPortfolioValuesFeed {
	/////////////////////////////////////////////
	/// external state changing functionality ///
	/////////////////////////////////////////////

    struct OptionStores {
		Types.OptionSeries optionSeries;
		int256 shortExposure;
		int256 longExposure;
	}

	/**
	 * @notice Creates a Chainlink request to update portfolio values
	 * data, then multiply by 1000000000000000000 (to remove decimal places from data).
	 *
	 * @return requestId - id of the request
	 */
	function requestPortfolioData(address _underlying, address _strike)
		external
		returns (bytes32 requestId);

	function updateStores(Types.OptionSeries memory _optionSeries, int256 _shortExposure, int256 _longExposure, address _seriesAddress) external;
    
	function netDhvExposure(bytes32 oHash) external view returns (int256);
	///////////////////////////
	/// non-complex getters ///
	///////////////////////////


	function getPortfolioValues(address underlying, address strike)
		external
		view
		returns (Types.PortfolioValues memory);

	function storesForAddress(address seriesAddress) external view returns (IAlphaPortfolioValuesFeed.OptionStores memory);
}