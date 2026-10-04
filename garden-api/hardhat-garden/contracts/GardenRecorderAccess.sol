// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title GardenRecorderAccess
 * @dev Control de acceso compartido por los contratos de registro de GARDEN.
 *
 * Dos roles separados:
 *  - owner: administra el contrato (cambia el recorder). Transferencia en dos
 *    pasos (Ownable2Step) para no perderlo por un error de tipeo. Conviene que
 *    sea un wallet frío que NO esté en el servidor.
 *  - recorder: el wallet del servidor (BLOCKCHAIN_PRIVATE_KEY en Render), el
 *    único que escribe registros. Si su clave se filtra, el owner lo reemplaza
 *    sin redesplegar ni perder el historial.
 *
 * Los contratos no tienen funciones payable ni receive/fallback: cualquier
 * envío de POL a estas direcciones se revierte.
 */
abstract contract GardenRecorderAccess is Ownable2Step {
    address public recorder;

    event RecorderChanged(address indexed previousRecorder, address indexed newRecorder);

    error NotRecorder(address caller);
    error ZeroAddress();
    error RenounceDisabled();

    constructor(address initialRecorder) Ownable(msg.sender) {
        _setRecorder(initialRecorder);
    }

    modifier onlyRecorder() {
        if (msg.sender != recorder) revert NotRecorder(msg.sender);
        _;
    }

    function setRecorder(address newRecorder) external onlyOwner {
        _setRecorder(newRecorder);
    }

    /// @dev Renunciar dejaría el contrato sin nadie que pueda rotar el recorder.
    function renounceOwnership() public view override onlyOwner {
        revert RenounceDisabled();
    }

    function _setRecorder(address newRecorder) private {
        if (newRecorder == address(0)) revert ZeroAddress();
        emit RecorderChanged(recorder, newRecorder);
        recorder = newRecorder;
    }
}
