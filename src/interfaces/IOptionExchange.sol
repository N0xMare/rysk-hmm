pragma solidity ^0.8.19;

import { Types } from "../libraries/Types.sol";
import { CombinedActions } from "../libraries/CombinedActions.sol";

interface IOptionExchange {

    struct OperationProcedures {
        CombinedActions.OperationType operation;
        CombinedActions.ActionArgs[] operationQueue;
    }

    function operate(OperationProcedures[] memory _operationProcedures) external;
}