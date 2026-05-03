// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title GardenEscrow v2
 * @dev Gestiona la lógica inmutable de reservas, disputas, extensiones y reputación para GARDEN.
 * Los pagos reales son off-chain (fiat), pero el estado y la reputación son on-chain.
 */
contract GardenEscrow {
    address public immutable owner;

    struct Booking {
        string bookingId;       // UUID de nuestra base de datos
        string clientId;        // ID del dueño
        string caregiverId;     // ID del cuidador
        uint256 amountBs;       // Monto total en Bs (para transparencia)
        uint256 startTime;      // Timestamp inicio
        uint256 endTime;        // Timestamp fin
        bool isActive;          // True cuando el pago fiat es confirmado
        bool isCompleted;       // True cuando el servicio finaliza bien
        uint8 rating;           // Calificación 1-5 (0 si no calificado)
        string petName;         // Nombre del peludo
        string serviceType;     // "HOSPEDAJE" o "PASEO"
    }

    mapping(string => Booking) public bookings;
    uint256 public totalBookings;

    // Reputación por cuidador: acumulado de ratings y conteo
    mapping(string => uint256) public caregiverTotalRating;
    mapping(string => uint256) public caregiverRatingCount;

    event BookingCreated(string indexed bookingId, string petName, uint256 amountBs);
    event PaymentConfirmed(string indexed bookingId, uint256 timestamp);
    event ServiceFinalized(string indexed bookingId, uint8 rating, uint256 timestamp);
    event ServiceCancelled(string indexed bookingId, string reason, uint256 timestamp);
    event DisputeResolved(
        string indexed bookingId,
        string verdict,
        uint256 caregiverAmountBs,
        uint256 clientDiscountBs,
        uint256 timestamp
    );
    event WalkExtended(
        string indexed bookingId,
        uint256 additionalMinutes,
        uint256 newAmountBs,
        uint256 timestamp
    );

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Solo el administrador de GARDEN puede llamar esta funcion"
        );
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Crea una nueva reserva en la blockchain (Escrow Virtual).
     * Se llama cuando el admin confirma el pago fiat.
     */
    function createBooking(
        string calldata _bookingId,
        string calldata _clientId,
        string calldata _caregiverId,
        uint256 _amountBs,
        uint256 _startTime,
        uint256 _endTime,
        string calldata _petName,
        string calldata _serviceType
    ) external onlyOwner {
        require(bookings[_bookingId].startTime == 0, "La reserva ya existe on-chain");

        bookings[_bookingId] = Booking({
            bookingId: _bookingId,
            clientId: _clientId,
            caregiverId: _caregiverId,
            amountBs: _amountBs,
            startTime: _startTime,
            endTime: _endTime,
            isActive: true,
            isCompleted: false,
            rating: 0,
            petName: _petName,
            serviceType: _serviceType
        });

        totalBookings++;

        emit BookingCreated(_bookingId, _petName, _amountBs);
        emit PaymentConfirmed(_bookingId, block.timestamp);
    }

    /**
     * @dev Finaliza el servicio y registra la calificación (Reputación Inmutable).
     * Actualiza el acumulado de reputación del cuidador.
     */
    function finalizeBooking(string calldata _bookingId, uint8 _rating) external onlyOwner {
        Booking storage b = bookings[_bookingId];
        require(b.isActive, "Reserva no activa o ya finalizada");
        require(!b.isCompleted, "Ya esta marcada como completada");
        require(_rating >= 1 && _rating <= 5, "La calificacion debe ser entre 1 y 5");

        b.isCompleted = true;
        b.isActive = false;
        b.rating = _rating;

        // Actualizar reputación acumulada del cuidador
        caregiverTotalRating[b.caregiverId] += _rating;
        caregiverRatingCount[b.caregiverId] += 1;

        emit ServiceFinalized(_bookingId, _rating, block.timestamp);
    }

    /**
     * @dev Cancela la reserva en el historial on-chain.
     */
    function cancelBooking(
        string calldata _bookingId,
        string calldata _reason
    ) external onlyOwner {
        Booking storage b = bookings[_bookingId];
        require(b.isActive, "No se puede cancelar una reserva inactiva o finalizada");

        b.isActive = false;

        emit ServiceCancelled(_bookingId, _reason, block.timestamp);
    }

    /**
     * @dev Resuelve una disputa a favor del cuidador.
     * Registra el monto pagado al cuidador.
     */
    function resolveDisputeCaregiverWins(
        string calldata _bookingId,
        uint256 _caregiverAmountBs
    ) external onlyOwner {
        Booking storage b = bookings[_bookingId];
        require(b.isActive, "Reserva no activa o ya resuelta");

        b.isActive = false;

        emit DisputeResolved(
            _bookingId,
            "CAREGIVER_WINS",
            _caregiverAmountBs,
            0,
            block.timestamp
        );
    }

    /**
     * @dev Resuelve una disputa a favor del cliente.
     * Registra el monto de reembolso.
     */
    function resolveDisputeClientWins(
        string calldata _bookingId,
        uint256 _refundAmountBs
    ) external onlyOwner {
        Booking storage b = bookings[_bookingId];
        require(b.isActive, "Reserva no activa o ya resuelta");

        b.isActive = false;

        emit DisputeResolved(
            _bookingId,
            "CLIENT_WINS",
            0,
            _refundAmountBs,
            block.timestamp
        );
    }

    /**
     * @dev Resuelve una disputa con pago parcial a ambas partes.
     */
    function resolvePartial(
        string calldata _bookingId,
        uint256 _caregiverAmountBs,
        uint256 _clientDiscountBs
    ) external onlyOwner {
        Booking storage b = bookings[_bookingId];
        require(b.isActive, "Reserva no activa o ya resuelta");

        b.isActive = false;

        emit DisputeResolved(
            _bookingId,
            "PARTIAL",
            _caregiverAmountBs,
            _clientDiscountBs,
            block.timestamp
        );
    }

    /**
     * @dev Registra la extensión de un paseo en curso.
     * Actualiza el monto total y extiende el tiempo de fin.
     */
    function extendWalk(
        string calldata _bookingId,
        uint256 _additionalMinutes,
        uint256 _newAmountBs
    ) external onlyOwner {
        Booking storage b = bookings[_bookingId];
        require(b.isActive, "Reserva no activa - no se puede extender");

        b.amountBs = _newAmountBs;
        b.endTime = b.endTime + (_additionalMinutes * 60);

        emit WalkExtended(_bookingId, _additionalMinutes, _newAmountBs, block.timestamp);
    }

    /**
     * @dev Obtiene la reputación on-chain de un cuidador.
     * @return totalRating Suma de todos los ratings recibidos.
     * @return ratingCount Número total de valoraciones.
     */
    function getReputation(
        string calldata _caregiverId
    ) external view returns (uint256 totalRating, uint256 ratingCount) {
        return (
            caregiverTotalRating[_caregiverId],
            caregiverRatingCount[_caregiverId]
        );
    }

    /**
     * @dev Obtiene info de una reserva (para transparencia en el frontend).
     */
    function getBooking(string calldata _id) external view returns (Booking memory) {
        return bookings[_id];
    }
}
