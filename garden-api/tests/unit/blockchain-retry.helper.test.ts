/**
 * Unit tests: dispatchOnChainWithRetry
 *
 * This helper is what actually gives blockchain writes retry + admin
 * visibility (createBooking/cancel/finalize/extend/resolveDispute*).
 * Covers: success on first try, success after a transient failure, and
 * exhausting all attempts → AdminNotification(BLOCKCHAIN_FAILURE) created.
 */

const mockAdminNotificationCreate = jest.fn().mockResolvedValue({});
const mockSendPushToAdmins = jest.fn().mockResolvedValue(undefined);

jest.mock('../../src/config/database.js', () => ({
  __esModule: true,
  default: {
    adminNotification: { create: mockAdminNotificationCreate },
  },
}));

jest.mock('../../src/services/firebase.service.js', () => ({
  __esModule: true,
  sendPushToAdmins: mockSendPushToAdmins,
}));

import { dispatchOnChainWithRetry } from '../../src/services/blockchain-retry.helper.js';

describe('dispatchOnChainWithRetry', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('succeeds on first attempt: calls onSuccess, never touches AdminNotification', async () => {
    const action = jest.fn().mockResolvedValue('0xTX');
    const onSuccess = jest.fn().mockResolvedValue(undefined);

    await dispatchOnChainWithRetry({ bookingId: 'b1', label: 'test', action, onSuccess });

    expect(action).toHaveBeenCalledTimes(1);
    expect(onSuccess).toHaveBeenCalledWith('0xTX');
    expect(mockAdminNotificationCreate).not.toHaveBeenCalled();
    expect(mockSendPushToAdmins).not.toHaveBeenCalled();
  });

  it('treats a legitimate null (mock mode / no-op) as success — no retry, no onSuccess, no alert', async () => {
    const action = jest.fn().mockResolvedValue(null);
    const onSuccess = jest.fn();

    await dispatchOnChainWithRetry({ bookingId: 'b2', label: 'test', action, onSuccess });

    expect(action).toHaveBeenCalledTimes(1);
    expect(onSuccess).not.toHaveBeenCalled();
    expect(mockAdminNotificationCreate).not.toHaveBeenCalled();
  });

  it('retries on thrown error and succeeds on the 2nd attempt', async () => {
    const action = jest.fn()
      .mockRejectedValueOnce(new Error('network blip'))
      .mockResolvedValueOnce('0xTX2');
    const onSuccess = jest.fn().mockResolvedValue(undefined);

    await dispatchOnChainWithRetry({ bookingId: 'b3', label: 'test', action, onSuccess, maxAttempts: 3 });

    expect(action).toHaveBeenCalledTimes(2);
    expect(onSuccess).toHaveBeenCalledWith('0xTX2');
    expect(mockAdminNotificationCreate).not.toHaveBeenCalled();
  }, 10000);

  it('exhausts all attempts and creates a BLOCKCHAIN_FAILURE AdminNotification', async () => {
    const action = jest.fn().mockRejectedValue(new Error('always fails'));
    const onSuccess = jest.fn();

    await dispatchOnChainWithRetry({ bookingId: 'b4', label: 'test', action, onSuccess, maxAttempts: 3 });

    expect(action).toHaveBeenCalledTimes(3);
    expect(onSuccess).not.toHaveBeenCalled();
    expect(mockAdminNotificationCreate).toHaveBeenCalledWith({
      data: { type: 'BLOCKCHAIN_FAILURE', bookingId: 'b4', caregiverId: '' },
    });
    expect(mockSendPushToAdmins).toHaveBeenCalledTimes(1);
    expect(mockSendPushToAdmins.mock.calls[0][1]).toContain('B4');
    expect(mockSendPushToAdmins.mock.calls[0][2]).toEqual({ type: 'BLOCKCHAIN_FAILURE', bookingId: 'b4' });
  }, 10000);

  it('never throws to the caller, even when AdminNotification.create itself fails', async () => {
    mockAdminNotificationCreate.mockRejectedValueOnce(new Error('db down'));
    const action = jest.fn().mockRejectedValue(new Error('always fails'));

    await expect(
      dispatchOnChainWithRetry({ bookingId: 'b5', label: 'test', action, maxAttempts: 2 })
    ).resolves.toBeUndefined();
  }, 10000);
});
