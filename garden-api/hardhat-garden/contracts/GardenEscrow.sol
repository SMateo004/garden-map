// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {GardenRecorderAccess} from "./GardenRecorderAccess.sol";

/**
 * @title GardenEscrow v3
 * @dev Registro público e inmutable del ciclo de vida de cada reserva de GARDEN.
 * No custodia dinero (los pagos son fiat, fuera de la cadena): solo deja
 * constancia de qué se pagó, cuándo y cómo terminó.
 *
 * Privacidad: no acepta ningún string. La reserva se identifica por su uuid
 * (bytes16) y las personas solo por una referencia seudónima (bytes32) que el
 * servidor calcula con un HMAC secreto de su id interno — desde la cadena no se
 * puede llegar a un nombre, teléfono ni correo. Montos en centavos de Bs.
 *
 * Reglas de estado: el registro de pago se hace una sola vez; finalizar,
 * cancelar y extender solo sobre una reserva activa; el veredicto de una
 * disputa se acepta en cualquier estado (una disputa por no-show llega con la
 * reserva ya cancelada, y una apelación puede reemplazar el veredicto anterior:
 * cada uno queda como evento).
 */
contract GardenEscrow is GardenRecorderAccess {
    uint256 public constant VERSION = 3;
    uint8 public constant MAX_CANCEL_REASON = 7;

    enum ServiceType { NONE, PASEO, HOSPEDAJE, GUARDERIA }
    enum Status { NONE, ACTIVE, COMPLETED, CANCELLED, RESOLVED }
    enum Verdict { NONE, CAREGIVER_WINS, CLIENT_WINS, PARTIAL }
    enum ExtensionUnit { NONE, MINUTES, DAYS }

    struct Booking {
        bytes32 clientRef;
        bytes32 caregiverRef;
        uint128 amountCents;
        uint64 paidAt;
        uint64 recordedAt;
        uint64 startTime;
        uint64 endTime;
        ServiceType serviceType;
        Status status;
        uint8 rating;
        uint8 cancelReason;
        Verdict verdict;
    }

    mapping(bytes16 => Booking) private _bookings;
    uint256 public totalBookings;

    mapping(bytes32 => uint256) public caregiverRatingSum;
    mapping(bytes32 => uint256) public caregiverRatingCount;

    event BookingRecorded(
        bytes16 indexed bookingId,
        bytes32 indexed clientRef,
        bytes32 indexed caregiverRef,
        ServiceType serviceType,
        uint128 amountCents,
        uint64 paidAt,
        uint64 startTime,
        uint64 endTime
    );
    event BookingFinalized(bytes16 indexed bookingId, uint8 rating);
    event BookingCancelled(bytes16 indexed bookingId, uint8 reasonCode, uint128 refundCents);
    event DisputeResolved(bytes16 indexed bookingId, Verdict verdict, uint128 caregiverCents, uint128 clientCents);
    event BookingExtended(
        bytes16 indexed bookingId,
        ExtensionUnit unit,
        uint32 quantity,
        uint128 newAmountCents,
        uint64 newEndTime
    );

    error InvalidInput();
    error AlreadyRecorded(bytes16 bookingId);
    error UnknownBooking(bytes16 bookingId);
    error NotActive(bytes16 bookingId, Status status);

    constructor(address initialRecorder) GardenRecorderAccess(initialRecorder) {}

    function recordBooking(
        bytes16 bookingId,
        bytes32 clientRef,
        bytes32 caregiverRef,
        ServiceType serviceType,
        uint128 amountCents,
        uint64 paidAt,
        uint64 startTime,
        uint64 endTime
    ) external onlyRecorder {
        if (
            bookingId == bytes16(0) || clientRef == bytes32(0) || caregiverRef == bytes32(0) ||
            serviceType == ServiceType.NONE || paidAt == 0 || startTime == 0 || endTime < startTime
        ) revert InvalidInput();
        Booking storage b = _bookings[bookingId];
        if (b.status != Status.NONE) revert AlreadyRecorded(bookingId);

        b.clientRef = clientRef;
        b.caregiverRef = caregiverRef;
        b.amountCents = amountCents;
        b.paidAt = paidAt;
        b.recordedAt = uint64(block.timestamp);
        b.startTime = startTime;
        b.endTime = endTime;
        b.serviceType = serviceType;
        b.status = Status.ACTIVE;
        totalBookings++;

        emit BookingRecorded(bookingId, clientRef, caregiverRef, serviceType, amountCents, paidAt, startTime, endTime);
    }

    /// @param rating 1-5, o 0 si el dueño no calificó (liberación automática del pago).
    function finalizeBooking(bytes16 bookingId, uint8 rating) external onlyRecorder {
        if (rating > 5) revert InvalidInput();
        Booking storage b = _active(bookingId);
        b.status = Status.COMPLETED;
        b.rating = rating;
        if (rating > 0) {
            caregiverRatingSum[b.caregiverRef] += rating;
            caregiverRatingCount[b.caregiverRef] += 1;
        }
        emit BookingFinalized(bookingId, rating);
    }

    /// @param reasonCode código numérico del motivo (ver blockchain.service.ts), nunca texto libre.
    function cancelBooking(bytes16 bookingId, uint8 reasonCode, uint128 refundCents) external onlyRecorder {
        if (reasonCode > MAX_CANCEL_REASON) revert InvalidInput();
        Booking storage b = _active(bookingId);
        b.status = Status.CANCELLED;
        b.cancelReason = reasonCode;
        emit BookingCancelled(bookingId, reasonCode, refundCents);
    }

    function resolveDispute(
        bytes16 bookingId,
        Verdict verdict,
        uint128 caregiverCents,
        uint128 clientCents
    ) external onlyRecorder {
        if (verdict == Verdict.NONE) revert InvalidInput();
        Booking storage b = _bookings[bookingId];
        if (b.status == Status.NONE) revert UnknownBooking(bookingId);
        b.status = Status.RESOLVED;
        b.verdict = verdict;
        emit DisputeResolved(bookingId, verdict, caregiverCents, clientCents);
    }

    function extendBooking(
        bytes16 bookingId,
        ExtensionUnit unit,
        uint32 quantity,
        uint128 newAmountCents
    ) external onlyRecorder {
        if (unit == ExtensionUnit.NONE || quantity == 0) revert InvalidInput();
        Booking storage b = _active(bookingId);
        uint64 secondsPerUnit = unit == ExtensionUnit.MINUTES ? 60 : 86400;
        b.endTime = b.endTime + uint64(quantity) * secondsPerUnit;
        b.amountCents = newAmountCents;
        emit BookingExtended(bookingId, unit, quantity, newAmountCents, b.endTime);
    }

    function getBooking(bytes16 bookingId) external view returns (Booking memory) {
        return _bookings[bookingId];
    }

    function getReputation(bytes32 caregiverRef) external view returns (uint256 totalRating, uint256 ratingCount) {
        return (caregiverRatingSum[caregiverRef], caregiverRatingCount[caregiverRef]);
    }

    function _active(bytes16 bookingId) private view returns (Booking storage b) {
        b = _bookings[bookingId];
        if (b.status == Status.NONE) revert UnknownBooking(bookingId);
        if (b.status != Status.ACTIVE) revert NotActive(bookingId, b.status);
    }
}
