// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title GardenEscrow
 * @dev Gestiona la lógica inmutable de reservas, "escrow virtual" y reputación para GARDEN.
 * Los pagos reales son off-chain (fiat), pero el estado y la reputación son on-chain.
 */
contract GardenEscrow {
    address public immutable owner; // Tú (la plataforma/admin)
    
    // Estructura de una reserva adaptada al contexto de GARDEN
    struct Booking {
        string bookingId;           // UUID de nuestra base de datos
        string clientId;            // ID del dueño
        string caregiverId;         // ID del cuidador
        uint256 amountBs;           // Monto total en Bs (para transparencia)
        uint256 startTime;          // Timestamp inicio
        uint256 endTime;            // Timestamp fin
        bool isActive;              // True cuando el pago fiat es confirmado (Escrow Virtual)
        bool isCompleted;           // True cuando el servicio finaliza bien
        uint8 rating;               // Calificación 1-5 (0 si no calificado)
        string petName;             // Nombre del peludo
        string serviceType;         // "HOSPEDAJE" o "PASEO"
    }
    
    // Mapeo: ID de reserva (UUID string) → datos
    mapping(string => Booking) public bookings;
    uint256 public totalBookings;
    
    // Eventos para el backend
    event BookingCreated(string indexed bookingId, string petName, uint256 amountBs);
    event PaymentConfirmed(string indexed bookingId, uint256 timestamp);
    event ServiceFinalized(string indexed bookingId, uint8 rating, uint256 timestamp);
    event ServiceCancelled(string indexed bookingId, string reason, uint256 timestamp);
    event DisputeResolved(string indexed bookingId, string verdict, uint256 caregiverAmountBs, uint256 clientDiscountBs, uint256 timestamp);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Solo el administrador de GARDEN puede llamar esta funcion");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Crea una nueva reserva en la blockchain (Escrow Virtual).
     * Se llama desde el backend cuando el administrador confirma el pago fiat.
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
            isActive: true, // Se activa directamente al confirmarse el pago fiat
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
     */
    function finalizeBooking(string calldata _bookingId, uint8 _rating) external onlyOwner {
        Booking storage b = bookings[_bookingId];
        require(b.isActive, "Reserva no activa o ya finalizada");
        require(!b.isCompleted, "Ya esta marcada como completada");
        require(_rating >= 1 && _rating <= 5, "La calificacion debe ser entre 1 y 5");
        
        b.isCompleted = true;
        b.isActive = false;
        b.rating = _rating;
        
        emit ServiceFinalized(_bookingId, _rating, block.timestamp);
    }
    
    /**
     * @dev Cancela la reserva en el historial on-chain.
     */
    function cancelBooking(string calldata _bookingId, string calldata _reason) external onlyOwner {
        Booking storage b = bookings[_bookingId];
        require(b.isActive, "No se puede cancelar una reserva inactiva o finalizada");
        
        b.isActive = false;
        
        emit ServiceCancelled(_bookingId, _reason, block.timestamp);
    }
    
    /**
     * @dev Resuelve una disputa con veredicto para el cuidador (pago total neto).
     * Finaliza la reserva on-chain y emite el evento de disputa resuelta.
     */
    function resolveDisputeCaregiverWins(
        string calldata _bookingId,
        uint256 _caregiverAmountBs
    ) external onlyOwner {
        Booking storage b = bookings[_bookingId];
        require(b.isActive, "Reserva no activa");

        b.isActive = false;
        b.isCompleted = true;
        b.rating = 3;

        emit DisputeResolved(_bookingId, "CAREGIVER_WINS", _caregiverAmountBs, 0, block.timestamp);
        emit ServiceFinalized(_bookingId, 3, block.timestamp);
    }

    /**
     * @dev Resuelve una disputa con veredicto para el cliente (reembolso total).
     * Cancela la reserva on-chain y emite el evento de disputa resuelta.
     */
    function resolveDisputeClientWins(
        string calldata _bookingId,
        uint256 _refundAmountBs
    ) external onlyOwner {
        Booking storage b = bookings[_bookingId];
        require(b.isActive, "Reserva no activa");

        b.isActive = false;

        emit DisputeResolved(_bookingId, "CLIENT_WINS", 0, _refundAmountBs, block.timestamp);
        emit ServiceCancelled(_bookingId, "Disputa resuelta a favor del cliente", block.timestamp);
    }

    /**
     * @dev Resuelve una disputa con veredicto parcial:
     *      80% del monto neto al cuidador + 20% convertido en codigo de descuento para el dueno.
     *      La comision (10%) ya fue descontada off-chain antes de llamar esta funcion.
     * @param _caregiverAmountBs 80% del monto neto (en Bs, sin decimales)
     * @param _clientDiscountBs  20% del monto neto convertido en descuento para el dueno
     */
    function resolvePartial(
        string calldata _bookingId,
        uint256 _caregiverAmountBs,
        uint256 _clientDiscountBs
    ) external onlyOwner {
        Booking storage b = bookings[_bookingId];
        require(b.isActive, "Reserva no activa");
        require(_caregiverAmountBs + _clientDiscountBs <= b.amountBs, "Montos exceden el total registrado");

        b.isActive = false;
        b.isCompleted = true;
        b.rating = 3; // calificacion neutral para disputa parcial

        emit DisputeResolved(_bookingId, "PARTIAL", _caregiverAmountBs, _clientDiscountBs, block.timestamp);
        emit ServiceFinalized(_bookingId, 3, block.timestamp);
    }

    /**
     * @dev Obtiene info de una reserva (para transparencia en el frontend)
     */
    function getBooking(string calldata _id) external view returns (Booking memory) {
        return bookings[_id];
    }
}
