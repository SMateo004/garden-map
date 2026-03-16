/**
 * Tabla comparativa de reglas de cancelación y reembolso (MVP Subfase 2.2).
 * Muestra políticas diferenciales para hospedaje (48h/24h) y paseos (12h/6h).
 */

export function CancellationRulesTable() {
  return (
    <div className="rounded-xl border border-gray-200 bg-gray-50 p-4">
      <h3 className="mb-3 text-sm font-semibold text-gray-900">Política de cancelación y reembolso</h3>
      <div className="overflow-x-auto">
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b border-gray-300">
              <th className="px-2 py-2 text-left font-medium text-gray-700">Antelación</th>
              <th className="px-2 py-2 text-center font-medium text-gray-700">Hospedaje</th>
              <th className="px-2 py-2 text-center font-medium text-gray-700">Paseos</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            <tr>
              <td className="px-2 py-2 text-gray-600">Más de 48h / 12h</td>
              <td className="px-2 py-2 text-center text-green-700 font-medium">100% - Bs 10</td>
              <td className="px-2 py-2 text-center text-green-700 font-medium">100%</td>
            </tr>
            <tr>
              <td className="px-2 py-2 text-gray-600">24-48h / 6-12h</td>
              <td className="px-2 py-2 text-center text-amber-700 font-medium">50%</td>
              <td className="px-2 py-2 text-center text-amber-700 font-medium">50%</td>
            </tr>
            <tr>
              <td className="px-2 py-2 text-gray-600">Menos de 24h / 6h</td>
              <td className="px-2 py-2 text-center text-red-700 font-medium">0%</td>
              <td className="px-2 py-2 text-center text-red-700 font-medium">0%</td>
            </tr>
          </tbody>
        </table>
      </div>
      <p className="mt-2 text-xs text-gray-500">
        Los reembolsos se procesan según la fecha y hora de cancelación respecto al inicio del servicio.
      </p>
    </div>
  );
}
