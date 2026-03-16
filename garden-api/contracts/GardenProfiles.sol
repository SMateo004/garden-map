// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title GardenProfiles
 * @dev Gestiona el registro inmutable de identidades y perfiles en GARDEN.
 * Almacena el estado de verificación y datos básicos de confianza para dueños y cuidadores.
 */
contract GardenProfiles {
    address public immutable owner;

    enum UserRole { NONE, CLIENT, CAREGIVER }

    struct Profile {
        string userId;          // UUID de la base de datos
        string name;            // Nombre para mostrar
        UserRole role;          // CLIENT o CAREGIVER
        bool isVerified;        // Estado de verificación de identidad
        uint256 joinedAt;       // Timestamp de registro
        string metadataHash;    // Hash IPFS o JSON string con bio/fotos (opcional)
        bool exists;
    }

    struct PetSummary {
        string petName;
        string breed;
        uint256 lastUpdate;
    }

    // Mapeo: ID de usuario (UUID) -> Datos del perfil
    mapping(string => Profile) public profiles;
    // Mapeo: ID de dueño (UUID) -> Lista de mascotas básicas (creativo)
    mapping(string => PetSummary[]) public ownerPets;
    
    event ProfileSynced(string indexed userId, string name, UserRole role, bool isVerified);
    event VerificationStatusUpdated(string indexed userId, bool isVerified);
    event PetOnChainAdded(string indexed ownerId, string petName);

    modifier onlyOwner() {
        require(msg.sender == owner, "Solo el admin de GARDEN puede ejecutar esto");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Sincroniza un perfil de la base de datos a la blockchain.
     */
    function syncProfile(
        string calldata _userId,
        string calldata _name,
        uint8 _role,
        bool _isVerified,
        string calldata _metadataHash
    ) external onlyOwner {
        profiles[_userId] = Profile({
            userId: _userId,
            name: _name,
            role: UserRole(_role),
            isVerified: _isVerified,
            joinedAt: profiles[_userId].exists ? profiles[_userId].joinedAt : block.timestamp,
            metadataHash: _metadataHash,
            exists: true
        });

        emit ProfileSynced(_userId, _name, UserRole(_role), _isVerified);
    }

    /**
     * @dev Actualiza el estado de verificación por separado (ej. tras validación de CI).
     */
    function updateVerificationStatus(string calldata _userId, bool _status) external onlyOwner {
        require(profiles[_userId].exists, "El perfil no existe en blockchain");
        profiles[_userId].isVerified = _status;
        emit VerificationStatusUpdated(_userId, _status);
    }

    /**
     * @dev Agrega una mascota al perfil del dueño de forma creativa on-chain.
     */
    function addPetToOwner(string calldata _ownerId, string calldata _petName, string calldata _breed) external onlyOwner {
        require(profiles[_ownerId].exists, "El dueno debe tener perfil sincronizado");
        ownerPets[_ownerId].push(PetSummary({
            petName: _petName,
            breed: _breed,
            lastUpdate: block.timestamp
        }));
        emit PetOnChainAdded(_ownerId, _petName);
    }

    /**
     * @dev Consulta si un usuario está verificado (usado por otros contratos o frontend).
     */
    function isUserVerified(string calldata _userId) external view returns (bool) {
        return profiles[_userId].isVerified;
    }

    function getOwnerPetsCount(string calldata _ownerId) external view returns (uint256) {
        return ownerPets[_ownerId].length;
    }
}
