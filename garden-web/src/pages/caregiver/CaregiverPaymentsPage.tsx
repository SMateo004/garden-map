import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { getWallet, requestWithdrawal, updateBankInfo, type WalletData, type WalletTransaction } from '@/api/wallet';

const TX_LABELS: Record<string, string> = {
  EARNING: 'Ganancia',
  PAYMENT: 'Pago',
  REFUND: 'Regalo',
  WITHDRAWAL: 'Retiro',
  COMMISSION: 'Comisión',
};

const STATUS_STYLE: Record<string, string> = {
  COMPLETED: 'bg-green-100 text-green-700',
  PENDING: 'bg-amber-100 text-amber-700',
  PROCESSING: 'bg-blue-100 text-blue-700',
  REJECTED: 'bg-red-100 text-red-700',
};

const STATUS_LABEL: Record<string, string> = {
  COMPLETED: 'Completado',
  PENDING: 'Pendiente',
  PROCESSING: 'Procesando',
  REJECTED: 'Rechazado',
};

function TxIcon({ type }: { type: string }) {
  if (type === 'EARNING') return <span className="text-xl">💰</span>;
  if (type === 'WITHDRAWAL') return <span className="text-xl">🏦</span>;
  if (type === 'REFUND') return <span className="text-xl">🎁</span>;
  if (type === 'COMMISSION') return <span className="text-xl">📊</span>;
  return <span className="text-xl">💳</span>;
}

export function CaregiverPaymentsPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const [tab, setTab] = useState<'wallet' | 'bank'>('wallet');
  const [withdrawAmount, setWithdrawAmount] = useState('');
  const [bankForm, setBankForm] = useState({ bankName: '', bankAccount: '', bankHolder: '', bankType: '' });
  const [bankEditing, setBankEditing] = useState(false);
  const [txFilter, setTxFilter] = useState<'ALL' | 'EARNING' | 'WITHDRAWAL'>('ALL');

  const { data: wallet, isLoading } = useQuery<WalletData>({
    queryKey: ['wallet'],
    queryFn: getWallet,
  });

  // Populate bank form from fetched data
  useEffect(() => {
    if (wallet?.caregiverBankInfo && !bankEditing) {
      setBankForm({
        bankName: wallet.caregiverBankInfo.bankName ?? '',
        bankAccount: wallet.caregiverBankInfo.bankAccount ?? '',
        bankHolder: wallet.caregiverBankInfo.bankHolder ?? '',
        bankType: wallet.caregiverBankInfo.bankType ?? '',
      });
    }
  }, [wallet?.caregiverBankInfo]);

  const withdrawMutation = useMutation({
    mutationFn: (amount: number) => requestWithdrawal(amount),
    onSuccess: () => {
      toast.success('Solicitud de retiro enviada');
      setWithdrawAmount('');
      queryClient.invalidateQueries({ queryKey: ['wallet'] });
    },
    onError: (e: any) => toast.error(e?.response?.data?.error?.message ?? 'Error al solicitar retiro'),
  });

  const bankMutation = useMutation({
    mutationFn: updateBankInfo,
    onSuccess: () => {
      toast.success('Datos bancarios guardados');
      setBankEditing(false);
      queryClient.invalidateQueries({ queryKey: ['wallet'] });
    },
    onError: (e: any) => toast.error(e?.response?.data?.error?.message ?? 'Error al guardar datos bancarios'),
  });

  const handleWithdraw = (e: React.FormEvent) => {
    e.preventDefault();
    const amt = parseFloat(withdrawAmount);
    if (!amt || amt <= 0) { toast.error('Ingresa un monto válido'); return; }
    withdrawMutation.mutate(amt);
  };

  const handleBankSave = (e: React.FormEvent) => {
    e.preventDefault();
    if (!bankForm.bankName || !bankForm.bankAccount || !bankForm.bankHolder || !bankForm.bankType) {
      toast.error('Completa todos los datos bancarios');
      return;
    }
    bankMutation.mutate(bankForm);
  };

  if (isLoading) {
    return (
      <div className="min-h-screen bg-gray-50 dark:bg-gray-950 flex items-center justify-center">
        <p className="text-gray-500">Cargando finanzas…</p>
      </div>
    );
  }

  const balance = wallet?.balance ?? 0;
  const pendingWithdrawals = wallet?.pendingWithdrawals ?? 0;
  const availableBalance = Math.max(0, balance - pendingWithdrawals);
  const hasBankInfo = !!(wallet?.caregiverBankInfo?.bankName && wallet?.caregiverBankInfo?.bankAccount);

  const activePendingTx: WalletTransaction | undefined = wallet?.transactions.find(
    (t: WalletTransaction) => t.type === 'WITHDRAWAL' && (t.status === 'PENDING' || t.status === 'PROCESSING')
  );

  const filteredTx: WalletTransaction[] = (wallet?.transactions ?? []).filter((t: WalletTransaction) => {
    if (txFilter === 'ALL') return true;
    return t.type === txFilter;
  });

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950 pb-24">
      {/* Header */}
      <div className="bg-green-600 px-6 pt-12 pb-20 rounded-b-[3rem] shadow-xl text-white relative">
        <button
          onClick={() => navigate('/caregiver/dashboard')}
          className="absolute top-6 left-6 w-10 h-10 bg-white/20 backdrop-blur-md rounded-xl flex items-center justify-center text-white border border-white/20 hover:bg-white/30 transition-all"
        >
          ←
        </button>
        <div className="max-w-4xl mx-auto text-center">
          <p className="text-xs font-bold uppercase tracking-widest opacity-70 mb-1">Balance disponible</p>
          <h1 className="text-5xl font-black mb-1">Bs {availableBalance.toFixed(2)}</h1>
          {pendingWithdrawals > 0 && (
            <p className="text-sm opacity-80">Bs {pendingWithdrawals.toFixed(2)} en retiro pendiente</p>
          )}
        </div>
      </div>

      {/* Stats row */}
      <div className="max-w-4xl mx-auto px-4 -mt-10 grid grid-cols-3 gap-3 mb-6">
        {[
          { label: 'Total ganado', value: `Bs ${(wallet?.totalEarned ?? 0).toFixed(2)}`, color: 'text-green-600' },
          { label: 'Retirado', value: `Bs ${(wallet?.totalWithdrawn ?? 0).toFixed(2)}`, color: 'text-gray-800 dark:text-white' },
          { label: 'Balance total', value: `Bs ${balance.toFixed(2)}`, color: 'text-green-600' },
        ].map(s => (
          <div key={s.label} className="bg-white dark:bg-gray-900 rounded-2xl p-4 shadow border border-gray-100 dark:border-gray-800 text-center">
            <p className="text-[10px] text-gray-400 uppercase font-bold mb-1">{s.label}</p>
            <p className={`text-base font-black ${s.color}`}>{s.value}</p>
          </div>
        ))}
      </div>

      {/* Tabs */}
      <div className="max-w-4xl mx-auto px-4 mb-6">
        <div className="flex bg-white dark:bg-gray-900 p-1 rounded-2xl shadow border border-gray-100 dark:border-gray-800">
          {(['wallet', 'bank'] as const).map(t => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={`flex-1 py-2.5 rounded-xl text-sm font-bold transition-all ${
                tab === t ? 'bg-green-600 text-white shadow' : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              {t === 'wallet' ? '💰 Retiros' : '🏦 Banco'}
            </button>
          ))}
        </div>
      </div>

      <div className="max-w-4xl mx-auto px-4 space-y-6">

        {/* ── WALLET TAB ── */}
        {tab === 'wallet' && (
          <>
            {/* Active withdrawal status */}
            {activePendingTx && (
              <div className="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-2xl p-5">
                <div className="flex items-center gap-3">
                  <span className="text-2xl">⏳</span>
                  <div>
                    <p className="font-bold text-blue-800 dark:text-blue-300">Retiro en proceso</p>
                    <p className="text-sm text-blue-600 dark:text-blue-400">
                      Bs {activePendingTx.amount.toFixed(2)} · Estado:{' '}
                      <span className="font-bold uppercase">{STATUS_LABEL[activePendingTx.status]}</span>
                    </p>
                    <p className="text-xs text-blue-500 mt-0.5">
                      Solicitado el {new Date(activePendingTx.createdAt).toLocaleDateString()}
                    </p>
                  </div>
                </div>
              </div>
            )}

            {/* Withdrawal form */}
            <div className="bg-white dark:bg-gray-900 rounded-3xl shadow border border-gray-100 dark:border-gray-800 p-6">
              <h2 className="font-bold text-gray-900 dark:text-white mb-4">Solicitar retiro</h2>
              {!hasBankInfo ? (
                <div className="text-center py-4">
                  <p className="text-gray-500 text-sm mb-3">Configura tus datos bancarios primero</p>
                  <button
                    onClick={() => setTab('bank')}
                    className="px-4 py-2 bg-green-600 text-white rounded-xl text-sm font-bold"
                  >
                    Configurar banco →
                  </button>
                </div>
              ) : activePendingTx ? (
                <p className="text-sm text-gray-500 text-center py-2">
                  Ya tienes un retiro pendiente. Espera a que se complete antes de solicitar otro.
                </p>
              ) : (
                <form onSubmit={handleWithdraw} className="space-y-4">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                      Monto a retirar (Bs)
                    </label>
                    <div className="relative">
                      <span className="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 font-bold">Bs</span>
                      <input
                        type="number"
                        min="1"
                        step="0.01"
                        value={withdrawAmount}
                        onChange={e => setWithdrawAmount(e.target.value)}
                        placeholder="0.00"
                        className="w-full pl-12 pr-4 py-3 rounded-xl border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800 text-gray-900 dark:text-white focus:ring-2 focus:ring-green-500 outline-none"
                      />
                    </div>
                    <p className="text-xs text-gray-400 mt-1">
                      Disponible: Bs {availableBalance.toFixed(2)} · {wallet?.caregiverBankInfo?.bankHolder} · {wallet?.caregiverBankInfo?.bankName}
                    </p>
                  </div>
                  <button
                    type="submit"
                    disabled={withdrawMutation.isPending || !withdrawAmount}
                    className="w-full py-3 bg-green-600 hover:bg-green-700 disabled:opacity-50 text-white font-bold rounded-xl shadow-lg shadow-green-200 dark:shadow-none transition-all"
                  >
                    {withdrawMutation.isPending ? 'Enviando…' : 'Solicitar retiro'}
                  </button>
                </form>
              )}
            </div>

            {/* Transaction history */}
            <div className="bg-white dark:bg-gray-900 rounded-3xl shadow border border-gray-100 dark:border-gray-800 overflow-hidden">
              <div className="p-5 border-b border-gray-100 dark:border-gray-800 flex items-center justify-between">
                <h2 className="font-bold text-gray-900 dark:text-white">Historial</h2>
                <div className="flex gap-1">
                  {(['ALL', 'EARNING', 'WITHDRAWAL'] as const).map(f => (
                    <button
                      key={f}
                      onClick={() => setTxFilter(f)}
                      className={`px-3 py-1 rounded-lg text-xs font-bold transition-all ${
                        txFilter === f ? 'bg-green-600 text-white' : 'text-gray-400 hover:text-gray-700'
                      }`}
                    >
                      {f === 'ALL' ? 'Todo' : TX_LABELS[f]}
                    </button>
                  ))}
                </div>
              </div>
              {filteredTx.length === 0 ? (
                <div className="p-10 text-center text-gray-400 text-sm">Sin transacciones</div>
              ) : (
                <div>
                  {filteredTx.map((t: WalletTransaction, i: number) => (
                    <div
                      key={t.id}
                      className={`flex items-center gap-4 px-5 py-4 ${
                        i !== filteredTx.length - 1 ? 'border-b border-gray-50 dark:border-gray-800' : ''
                      }`}
                    >
                      <div className="w-10 h-10 bg-gray-50 dark:bg-gray-800 rounded-xl flex items-center justify-center shrink-0">
                        <TxIcon type={t.type} />
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="font-semibold text-gray-900 dark:text-white text-sm truncate">{t.description}</p>
                        <div className="flex items-center gap-2 mt-0.5">
                          <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded-full ${STATUS_STYLE[t.status]}`}>
                            {STATUS_LABEL[t.status]}
                          </span>
                          <span className="text-[10px] text-gray-400">
                            {new Date(t.createdAt).toLocaleDateString()}
                          </span>
                        </div>
                      </div>
                      <div className="text-right shrink-0">
                        <p className={`font-black text-sm ${
                          t.type === 'EARNING' || t.type === 'REFUND' ? 'text-green-600' :
                          t.type === 'WITHDRAWAL' && t.status === 'COMPLETED' ? 'text-red-500' :
                          t.type === 'WITHDRAWAL' ? 'text-amber-500' : 'text-gray-700 dark:text-gray-300'
                        }`}>
                          {t.type === 'EARNING' || t.type === 'REFUND' ? '+' : t.type === 'WITHDRAWAL' && t.status === 'COMPLETED' ? '−' : ''}
                          Bs {t.amount.toFixed(2)}
                        </p>
                        <p className="text-[10px] text-gray-400">saldo Bs {t.balance.toFixed(2)}</p>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </>
        )}

        {/* ── BANK TAB ── */}
        {tab === 'bank' && (
          <div className="bg-white dark:bg-gray-900 rounded-3xl shadow border border-gray-100 dark:border-gray-800 p-6">
            <h2 className="font-bold text-gray-900 dark:text-white mb-1">Datos bancarios</h2>
            <p className="text-xs text-gray-400 mb-6">
              Tu dinero se depositará en esta cuenta. Asegúrate de que los datos sean correctos.
            </p>
            <form onSubmit={handleBankSave} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Banco</label>
                <input
                  value={bankForm.bankName}
                  onChange={e => { setBankEditing(true); setBankForm(p => ({ ...p, bankName: e.target.value })); }}
                  placeholder="Ej: Banco BCP, Banco Unión, Tigo Money…"
                  className="w-full px-4 py-3 rounded-xl border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800 text-gray-900 dark:text-white focus:ring-2 focus:ring-green-500 outline-none"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Número de cuenta</label>
                <input
                  value={bankForm.bankAccount}
                  onChange={e => { setBankEditing(true); setBankForm(p => ({ ...p, bankAccount: e.target.value })); }}
                  placeholder="Ej: 1234567890"
                  className="w-full px-4 py-3 rounded-xl border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800 text-gray-900 dark:text-white focus:ring-2 focus:ring-green-500 outline-none font-mono"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Titular de la cuenta</label>
                <input
                  value={bankForm.bankHolder}
                  onChange={e => { setBankEditing(true); setBankForm(p => ({ ...p, bankHolder: e.target.value })); }}
                  placeholder="Nombre completo del titular"
                  className="w-full px-4 py-3 rounded-xl border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800 text-gray-900 dark:text-white focus:ring-2 focus:ring-green-500 outline-none"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Tipo de cuenta</label>
                <select
                  value={bankForm.bankType}
                  onChange={e => { setBankEditing(true); setBankForm(p => ({ ...p, bankType: e.target.value })); }}
                  className="w-full px-4 py-3 rounded-xl border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800 text-gray-900 dark:text-white focus:ring-2 focus:ring-green-500 outline-none"
                >
                  <option value="">Selecciona el tipo</option>
                  <option value="Caja de Ahorro">Caja de Ahorro</option>
                  <option value="Cuenta Corriente">Cuenta Corriente</option>
                  <option value="Billetera Móvil">Billetera Móvil (Tigo Money, Simple, etc.)</option>
                </select>
              </div>
              <button
                type="submit"
                disabled={bankMutation.isPending}
                className="w-full py-3 bg-green-600 hover:bg-green-700 disabled:opacity-50 text-white font-bold rounded-xl shadow-lg shadow-green-200 dark:shadow-none transition-all"
              >
                {bankMutation.isPending ? 'Guardando…' : 'Guardar datos bancarios'}
              </button>
            </form>

            {hasBankInfo && (
              <div className="mt-6 p-4 bg-green-50 dark:bg-green-900/20 rounded-2xl border border-green-100 dark:border-green-900/40 text-sm">
                <p className="font-bold text-green-800 dark:text-green-300 mb-2">Datos actuales</p>
                <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
                  <span className="text-gray-400">Banco:</span>
                  <span className="font-bold text-gray-700 dark:text-gray-300">{wallet?.caregiverBankInfo?.bankName}</span>
                  <span className="text-gray-400">Cuenta:</span>
                  <span className="font-bold text-gray-700 dark:text-gray-300 font-mono">{wallet?.caregiverBankInfo?.bankAccount}</span>
                  <span className="text-gray-400">Titular:</span>
                  <span className="font-bold text-gray-700 dark:text-gray-300">{wallet?.caregiverBankInfo?.bankHolder}</span>
                  <span className="text-gray-400">Tipo:</span>
                  <span className="font-bold text-gray-700 dark:text-gray-300">{wallet?.caregiverBankInfo?.bankType}</span>
                </div>
              </div>
            )}
          </div>
        )}

      </div>
    </div>
  );
}
