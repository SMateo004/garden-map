import { api } from './client';

export interface WalletTransaction {
  id: string;
  type: 'EARNING' | 'PAYMENT' | 'REFUND' | 'WITHDRAWAL' | 'COMMISSION';
  amount: number;
  balance: number;
  description: string;
  bookingId: string | null;
  status: 'COMPLETED' | 'PENDING' | 'PROCESSING' | 'REJECTED';
  createdAt: string;
}

export interface CaregiverBankInfo {
  bankName: string | null;
  bankAccount: string | null;
  bankHolder: string | null;
  bankType: string | null;
}

export interface WalletData {
  balance: number;
  totalEarned: number;
  totalPaid: number;
  totalWithdrawn: number;
  pendingWithdrawals: number;
  transactions: WalletTransaction[];
  caregiverBankInfo: CaregiverBankInfo | null;
}

export async function getWallet(): Promise<WalletData> {
  const res = await api.get<{ success: boolean; data: WalletData }>('/api/wallet');
  return res.data.data;
}

export async function requestWithdrawal(amount: number): Promise<{ id: string; message: string }> {
  const res = await api.post<{ success: boolean; data: { id: string; message: string } }>(
    '/api/wallet/withdraw',
    { amount }
  );
  return res.data.data;
}

export async function updateBankInfo(data: {
  bankName: string;
  bankAccount: string;
  bankHolder: string;
  bankType: string;
}): Promise<void> {
  await api.patch('/api/caregiver/bank-info', data);
}
