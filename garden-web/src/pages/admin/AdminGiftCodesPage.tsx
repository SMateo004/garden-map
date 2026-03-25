import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import { getGiftCodes, createGiftCode, toggleGiftCode, type GiftCodeItem } from '@/api/admin';

export function AdminGiftCodesPage() {
  const queryClient = useQueryClient();
  const { data, isLoading, error } = useQuery({
    queryKey: ['admin', 'gift-codes'],
    queryFn: getGiftCodes,
  });

  const createMutation = useMutation({
    mutationFn: createGiftCode,
    onSuccess: () => {
      toast.success('Código creado correctamente');
      queryClient.invalidateQueries({ queryKey: ['admin', 'gift-codes'] });
      setShowCreateForm(false);
    },
    onError: (e: any) => toast.error(e.message || 'Error al crear'),
  });

  const toggleMutation = useMutation({
    mutationFn: toggleGiftCode,
    onSuccess: () => {
      toast.success('Estado del código actualizado');
      queryClient.invalidateQueries({ queryKey: ['admin', 'gift-codes'] });
    },
    onError: (e: any) => toast.error(e.message || 'Error al alternar estado'),
  });

  const [showCreateForm, setShowCreateForm] = useState(false);
  const [formData, setFormData] = useState({
    code: '',
    amount: 0,
    maxUses: 1,
    expiresAt: ''
  });

  if (isLoading) return <div className="text-center py-12 text-gray-500">Cargando códigos…</div>;
  if (error) return <div className="text-red-500 py-12">Error: {error instanceof Error ? error.message : 'Error al cargar'}</div>;

  const codes = data || [];

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Códigos de Regalo</h1>
        <button
          onClick={() => setShowCreateForm(true)}
          className="px-4 py-2 bg-green-600 hover:bg-green-700 text-white rounded-xl font-bold text-sm shadow-md"
        >
          + Nuevo Código
        </button>
      </div>

      {showCreateForm && (
        <div className="bg-white dark:bg-gray-800 p-6 rounded-2xl border-2 border-green-500/20 shadow-xl space-y-4 animate-in fade-in slide-in-from-top-4 duration-300">
          <h2 className="text-lg font-bold text-gray-900 dark:text-white">Crear Código</h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-4">
            <div>
              <label className="block text-xs font-bold text-gray-400 uppercase mb-1 ml-1">Código</label>
              <input
                type="text"
                placeholder="GIFT2024"
                className="w-full px-4 py-2 rounded-xl bg-gray-50 dark:bg-gray-700 border border-gray-200 dark:border-gray-600 focus:ring-2 focus:ring-green-500 outline-none uppercase font-mono"
                onChange={(e) => setFormData({ ...formData, code: e.target.value })}
              />
            </div>
            <div>
              <label className="block text-xs font-bold text-gray-400 uppercase mb-1 ml-1">Monto (Bs)</label>
              <input
                type="number"
                placeholder="50"
                className="w-full px-4 py-2 rounded-xl bg-gray-50 dark:bg-gray-700 border border-gray-200 dark:border-gray-600 focus:ring-2 focus:ring-green-500 outline-none"
                onChange={(e) => setFormData({ ...formData, amount: Number(e.target.value) })}
              />
            </div>
            <div>
              <label className="block text-xs font-bold text-gray-400 uppercase mb-1 ml-1">Usos Máximos</label>
              <input
                type="number"
                placeholder="1"
                className="w-full px-4 py-2 rounded-xl bg-gray-50 dark:bg-gray-700 border border-gray-200 dark:border-gray-600 focus:ring-2 focus:ring-green-500 outline-none"
                onChange={(e) => setFormData({ ...formData, maxUses: Number(e.target.value) })}
              />
            </div>
            <div>
              <label className="block text-xs font-bold text-gray-400 uppercase mb-1 ml-1">Fecha Expiración</label>
              <input
                type="date"
                className="w-full px-4 py-2 rounded-xl bg-gray-50 dark:bg-gray-700 border border-gray-200 dark:border-gray-600 focus:ring-2 focus:ring-green-500 outline-none"
                onChange={(e) => setFormData({ ...formData, expiresAt: e.target.value })}
              />
            </div>
          </div>
          <div className="flex justify-end gap-3 mt-4 pt-4 border-t border-gray-100 dark:border-gray-700">
            <button
               onClick={() => setShowCreateForm(false)}
               className="px-4 py-2 text-sm font-bold text-gray-500 hover:text-gray-700"
            >
              Cancelar
            </button>
            <button
              onClick={() => createMutation.mutate(formData)}
              className="px-6 py-2 bg-green-600 hover:bg-green-700 text-white rounded-xl font-bold text-sm shadow-lg shadow-green-500/20"
            >
              Crear Código
            </button>
          </div>
        </div>
      )}

      <div className="overflow-hidden bg-white dark:bg-gray-800 rounded-2xl border border-gray-200 dark:border-gray-700 shadow-sm">
        <table className="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead className="bg-gray-50 dark:bg-gray-900/50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-bold text-gray-400 uppercase tracking-widest">Código</th>
              <th className="px-6 py-3 text-left text-xs font-bold text-gray-400 uppercase tracking-widest">Monto</th>
              <th className="px-6 py-3 text-left text-xs font-bold text-gray-400 uppercase tracking-widest">Usos</th>
              <th className="px-6 py-3 text-left text-xs font-bold text-gray-400 uppercase tracking-widest">Expiración</th>
              <th className="px-6 py-3 text-left text-xs font-bold text-gray-400 uppercase tracking-widest">Estado</th>
              <th className="px-6 py-3 text-left text-xs font-bold text-gray-400 uppercase tracking-widest">Acción</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200 dark:divide-gray-700 divide-x-0">
            {codes.length === 0 ? (
               <tr>
                 <td colSpan={6} className="px-6 py-12 text-center text-gray-500">No hay códigos de regalo creados.</td>
               </tr>
            ) : (
              codes.map((c) => (
                <tr key={c.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/30 transition-colors">
                  <td className="px-6 py-4 font-mono font-bold text-green-600 dark:text-green-400">{c.code}</td>
                  <td className="px-6 py-4 font-black">Bs {c.amount}</td>
                  <td className="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">
                    <span className="font-bold text-gray-900 dark:text-gray-100">{c.usedCount}</span> / {c.maxUses}
                  </td>
                  <td className="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">
                    {c.expiresAt ? new Date(c.expiresAt).toLocaleDateString() : '∞'}
                  </td>
                  <td className="px-6 py-4">
                    <span className={`px-2 py-0.5 rounded-full text-[10px] font-black uppercase tracking-widest ${
                      c.active ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'
                    }`}>
                      {c.active ? 'Activo' : 'Inactivo'}
                    </span>
                  </td>
                  <td className="px-6 py-4">
                     <button
                       onClick={() => toggleMutation.mutate(c.id)}
                       className={`p-2 rounded-lg text-xs font-bold uppercase transition-all ${
                         c.active ? 'text-red-500 hover:bg-red-50' : 'text-green-500 hover:bg-green-50'
                       }`}
                     >
                        {c.active ? 'Desactivar' : 'Activar'}
                     </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
