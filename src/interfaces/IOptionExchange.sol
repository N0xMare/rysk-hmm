pragma solidity ^0.8.19;

import { Types } from "../libraries/Types.sol";
import { CombinedActions } from "../libraries/CombinedActions.sol";

interface IOptionExchange {

    struct OperationProcedures {
        CombinedActions.OperationType operation;
        CombinedActions.ActionArgs[] operationQueue;
    }

    function checkHash(
		Types.OptionSeries memory optionSeries,
		uint128 strikeDecimalConverted,
		bool isSell
	) external returns (bytes32 oHash);

    function getOptionDetails(
		address seriesAddress,
		Types.OptionSeries memory optionSeries
	) external view returns (address, Types.OptionSeries memory, uint128);

    function createOtoken(Types.OptionSeries memory optionSeries) external returns (address);

    function operate(OperationProcedures[] memory _operationProcedures) external;
}