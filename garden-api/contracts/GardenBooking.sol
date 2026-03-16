// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title GardenBooking
 * @dev Gestiona la lógica inmutable de reservas y calificaciones de GARDEN.
 * Los pagos reales son off-chain (fiat), pero el estado y la reputación son on-chain.
 */
contract GardenBooking {
    address public admin;

    enum BookingStatus { NONE, ACTIVE, COMPLETED, CANCELLED }

    struct Booking {
        string id;
        string clientId;
        string caregiverId;
        BookingStatus status;
        uint8 rating; // 0 if not rated yet, 1-5 otherwise
        uint256 createdAt;
        uint256 completedAt;
    }

    mapping(string => Booking) public bookings;
    mapping(string => uint256) public caregiverTotalRating;
    mapping(string => uint256) public caregiverReviewCount;

    event BookingRegistered(string bookingId, string clientId, string caregiverId, uint256 timestamp);
    event BookingCompleted(string bookingId, uint8 rating, uint256 timestamp);
    event BookingCancelled(string bookingId, string reason, uint256 timestamp);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Solo el administrador puede realizar esta accion");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    /**
     * @dev Registra una nueva reserva cuando el pago fiat es confirmado.
     */
    function registerBooking(
        string memory _bookingId,
        string memory _clientId,
        string memory _caregiverId
    ) external onlyAdmin {
        require(bytes(_bookingId).length > 0, "ID de reserva invalido");
        require(bookings[_bookingId].status == BookingStatus.NONE, "Reserva ya existe");

        bookings[_bookingId] = Booking({
            id: _bookingId,
            clientId: _clientId,
            caregiverId: _caregiverId,
            status: BookingStatus.ACTIVE,
            rating: 0,
            createdAt: block.timestamp,
            completedAt: 0
        });

        emit BookingRegistered(_bookingId, _clientId, _caregiverId, block.timestamp);
    }

    /**
     * @dev Marca una reserva como completada y registra la calificacion.
     */
    function completeBooking(string memory _bookingId, uint8 _rating) external onlyAdmin {
        require(bookings[_bookingId].status == BookingStatus.ACTIVE, "Reserva no activa");
        require(_rating >= 1 && _rating <= 5, "Calificacion debe ser entre 1 y 5");

        Booking storage b = bookings[_bookingId];
        b.status = BookingStatus.COMPLETED;
        b.rating = _rating;
        b.completedAt = block.timestamp;

        caregiverTotalRating[b.caregiverId] += _rating;
        caregiverReviewCount[b.caregiverId] += 1;

        emit BookingCompleted(_bookingId, _rating, block.timestamp);
    }

    /**
     * @dev Cancela una reserva.
     */
    function cancelBooking(string memory _bookingId, string memory _reason) external onlyAdmin {
        require(bookings[_bookingId].status == BookingStatus.ACTIVE, "Reserva no activa o ya finalizada");

        bookings[_bookingId].status = BookingStatus.CANCELLED;

        emit BookingCancelled(_bookingId, _reason, block.timestamp);
    }

    /**
     * @dev Obtiene el promedio de calificacion de un cuidador.
     */
    function getCaregiverRating(string memory _caregiverId) external view returns (uint256 average, uint256 count) {
        count = caregiverReviewCount[_caregiverId];
        if (count == 0) return (0, 0);
        average = (caregiverTotalRating[_caregiverId] * 10) / count; // Multiplicado por 10 para un decimal (ej: 4.5 -> 45)
        return (average, count);
    }

    /**
     * @dev Transfiere la administracion a una nueva cuenta.
     */
    function transferAdmin(address _newAdmin) external onlyAdmin {
        require(_newAdmin != address(0), "Direccion invalida");
        admin = _newAdmin;
    }
}
