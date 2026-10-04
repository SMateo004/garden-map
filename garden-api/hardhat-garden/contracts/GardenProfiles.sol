// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {GardenRecorderAccess} from "./GardenRecorderAccess.sol";

/**
 * @title GardenProfiles v2
 * @dev Registro de identidades de GARDEN: solo una referencia seudónima
 * (bytes32, HMAC secreto del id interno calculado en el servidor), el rol y si
 * la identidad fue verificada. Sin nombres, sin mascotas, sin metadatos: no
 * acepta ningún string. La v1 guardaba el nombre de cada usuario y de cada
 * mascota en texto plano.
 */
contract GardenProfiles is GardenRecorderAccess {
    uint256 public constant VERSION = 2;

    enum Role { NONE, CLIENT, CAREGIVER }

    struct Profile {
        Role role;
        bool verified;
        uint64 joinedAt;
        uint64 updatedAt;
    }

    mapping(bytes32 => Profile) private _profiles;
    uint256 public totalProfiles;

    event ProfileSynced(bytes32 indexed userRef, Role role, bool verified);

    error InvalidInput();

    constructor(address initialRecorder) GardenRecorderAccess(initialRecorder) {}

    function syncProfile(bytes32 userRef, Role role, bool verified) external onlyRecorder {
        if (userRef == bytes32(0) || role == Role.NONE) revert InvalidInput();
        Profile storage p = _profiles[userRef];
        if (p.joinedAt == 0) {
            p.joinedAt = uint64(block.timestamp);
            totalProfiles++;
        }
        p.role = role;
        p.verified = verified;
        p.updatedAt = uint64(block.timestamp);
        emit ProfileSynced(userRef, role, verified);
    }

    function getProfile(bytes32 userRef) external view returns (Profile memory) {
        return _profiles[userRef];
    }

    function isUserVerified(bytes32 userRef) external view returns (bool) {
        return _profiles[userRef].verified;
    }
}
