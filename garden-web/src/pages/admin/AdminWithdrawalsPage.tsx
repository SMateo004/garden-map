import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import { getWithdrawals, processWithdrawal, completeWithdrawal, rejectWithdrawal, type WithdrawalItem } from '@/api/admin';

export function AdminWithdrawalsPage() {
  const queryClient = useQueryClient();
  const [statusFilter, setStatusFilter] = useState('PENDING');

  const { data, isLoading, error } = useQuery({
    queryKey: ['admin', 'withdrawals', statusFilter],
    queryFn: () => getWithdrawals(statusFilter || undefined),
  });

  const processMutation = useMutation({
    mutationFn: processWithdrawal,
    onSuccess: () => {
      toast.success('Retiro marcado como PROCESANDO');
      queryClient.invalidateQueries({ queryKey: ['admin', 'withdrawals'] });
    },
    onError: (e: any) => toast.error(e.message || 'Error al procesar'),
  });

  const completeMutation = useMutation({
    mutationFn: completeWithdrawal,
    onSuccess: () => {
      toast.success('Retiro COMPLETADO correctamente');
      queryClient.invalidateQueries({ queryKey: ['admin', 'withdrawals'] });
    },
    onError: (e: any) => toast.error(e.message || 'Error al completar'),
  });

  const rejectMutation = useMutation({
    mutationFn: ({ id, reason }: { id: string; reason: string }) => rejectWithdrawal(id, reason),
    onSuccess: () => {
      toast.success('Retiro RECHAZADO');
      queryClient.invalidateQueries({ queryKey: ['admin', 'withdrawals'] });
    },
    onError: (e: any) => toast.error(e.message || 'Error al rechazar'),
  });

  const handleReject = (id: string) => {
    const reason = window.prompt('Indica el motivo del rechazo:');
    if (reason) rejectMutation.mutate({ id, reason });
  };

  if (isLoading) return <div className="text-center py-12 text-gray-500">Cargando retiros…</div>;
  if (error) return <div className="text-red-500 py-12">Error: {error instanceof Error ? error.message : 'Error al cargar'}</div>;

  const withdrawals = data || [];

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Gestión de Retiros</h1>
        <div className="flex bg-gray-100 dark:bg-gray-800 p-1 rounded-xl">
           {['PENDING', 'PROCESSING', 'COMPLETED', 'REJECTED'].map((s) => (
             <button
               key={s}
               onClick={() => setStatusFilter(s)}
               className={`px-4 py-2 rounded-lg text-xs font-bold transition-all ${
                 statusFilter === s
                   ? 'bg-white dark:bg-gray-700 text-green-600 dark:text-green-400 shadow-sm'
                   : 'text-gray-500 dark:text-gray-400 hover:text-gray-700'
               }`}
             >
               {s}
             </button>
           ))}
        </div>
      </div>

      <div className="grid gap-4">
        {withdrawals.length === 0 ? (
          <div className="bg-white dark:bg-gray-800 p-12 text-center rounded-2xl border border-gray-200 dark:border-gray-700 text-gray-500">
             No hay solicitudes de retiro en este estado.
          </div>
        ) : (
          withdrawals.map((w: WithdrawalItem) => (
            <div key={w.id} className="bg-white dark:bg-gray-800 p-6 rounded-2xl border border-gray-200 dark:border-gray-700 shadow-sm flex flex-col md:flex-row justify-between gap-6">
              <div className="space-y-2">
                <div className="flex items-center gap-2">
                  <h3 className="font-bold text-lg text-gray-900 dark:text-white">Bs {w.amount}</h3>
                  <span className={`px-2 py-0.5 rounded-full text-[10px] font-black uppercase tracking-widest ${
                    w.status === 'COMPLETED' ? 'bg-green-100 text-green-700' :
                    w.status === 'REJECTED' ? 'bg-red-100 text-red-700' :
                    w.status === 'PROCESSING' ? 'bg-blue-100 text-blue-700' : 'bg-amber-100 text-amber-700'
                  }`}>
                    {w.status}
                  </span>
                </div>
                <div className="text-sm">
                  <p className="font-bold text-gray-900 dark:text-gray-100">{w.user.firstName} {w.user.lastName}</p>
                  <p className="text-gray-500">{w.user.email}</p>
                </div>
                {w.user.caregiverProfile && (
                  <div className="mt-4 p-3 bg-gray-50 dark:bg-gray-900/40 rounded-xl border border-gray-100 dark:border-gray-700 text-xs grid grid-cols-2 gap-x-4 gap-y-1">
                    <span className="text-gray-400">Banco:</span> <span className="font-bold text-gray-700 dark:text-gray-300">{w.user.caregiverProfile.bankName}</span>
                    <span className="text-gray-400">Cuenta:</span> <span className="font-bold text-gray-700 dark:text-gray-300 font-mono">{w.user.caregiverProfile.bankAccount}</span>
                    <span className="text-gray-400">Titular:</span> <span className="font-bold text-gray-700 dark:text-gray-300 uppercase">{w.user.caregiverProfile.bankHolder}</span>
                    <span className="text-gray-400">Tipo:</span> <span className="font-bold text-gray-700 dark:text-gray-300">{w.user.caregiverProfile.bankType}</span>
                  </div>
                )}
                <p className="text-[10px] text-gray-400 uppercase tracking-tighter">ID: {w.id} · Creado: {new Date(w.createdAt).toLocaleString()}</p>
              </div>

              <div className="flex flex-col gap-2 self-center shrink-0 min-w-[200px]">
                {w.status === 'PENDING' && (
                  <button
                    onClick={() => processMutation.mutate(w.id)}
                    className="w-full py-3 bg-blue-600 hover:bg-blue-700 text-white rounded-xl font-bold text-sm shadow-lg shadow-blue-500/20 transition-all hover:scale-105 active:scale-95"
                  >
                    Procesar Retiro
                  </button>
                )}
                {(w.status === 'PENDING' || w.status === 'PROCESSING') && (
                  <button
                    onClick={() => completeMutation.mutate(w.id)}
                    className="w-full py-3 bg-green-600 hover:bg-green-700 text-white rounded-xl font-bold text-sm shadow-lg shadow-green-500/20 transition-all hover:scale-105 active:scale-95"
                  >
                    Marcar Completado
                  </button>
                )}
                {(w.status === 'PENDING' || w.status === 'PROCESSING') && (
                  <button
                    onClick={() => handleReject(w.id)}
                    className="w-full py-3 bg-white dark:bg-gray-700 border border-red-200 dark:border-red-900/30 text-red-600 dark:text-red-400 rounded-xl font-bold text-sm hover:bg-red-50 dark:hover:bg-red-900/10 transition-all"
                  >
                    Rechazar
                  </button>
                )}
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
