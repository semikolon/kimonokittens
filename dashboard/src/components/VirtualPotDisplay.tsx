interface VirtualPotProps {
  building_ops: {
    next_invoice_date: string;
    next_invoice_amount: number;
    days_until: number;
    pot_balance: number;
    shortfall: number;
  };
  gas: {
    next_refill_date: string;
    next_refill_amount: number;
    days_until: number;
    pot_balance: number;
    shortfall: number;
  };
}

export function VirtualPotDisplay({ building_ops, gas }: VirtualPotProps) {
  // Format date as "apr 2026"
  const formatDate = (dateStr: string) => {
    const date = new Date(dateStr);
    const months = ['jan', 'feb', 'mar', 'apr', 'maj', 'jun',
                   'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];
    return `${months[date.getMonth()]} ${date.getFullYear()}`;
  };

  // Format amount with space: "3 030 kr"
  const formatKr = (amount: number) => {
    return amount.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + ' kr';
  };

  return (
    <div className="virtual-pot-lines text-xs opacity-70 mt-2 space-y-1">
      <div className="pot-line">
        📊 Nästa driftavi: ~{building_ops.days_until} dagar
        ({formatDate(building_ops.next_invoice_date)}, {formatKr(building_ops.next_invoice_amount)})
        <br />
        &nbsp;&nbsp;&nbsp;Sparat hittills: {formatKr(building_ops.pot_balance)} |
        {' '}Behöver: {formatKr(building_ops.shortfall)} extra
      </div>

      <div className="pot-line">
        ⛽ Nästa gasol: ~{gas.days_until} dagar
        ({formatDate(gas.next_refill_date)}, {formatKr(gas.next_refill_amount)})
        <br />
        &nbsp;&nbsp;&nbsp;Sparat hittills: {formatKr(gas.pot_balance)} |
        {' '}Behöver: {formatKr(gas.shortfall)} extra
      </div>
    </div>
  );
}
