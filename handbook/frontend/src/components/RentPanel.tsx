import React, { useState, useEffect } from 'react';
import { TrendingUp, TrendingDown, AlertCircle } from 'lucide-react';

interface RentData {
  Total: number;
  'Rent per Roommate': { [name: string]: number };
}

const RentPanel: React.FC = () => {
  const [rentData, setRentData] = useState<RentData | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchRentData = async () => {
      try {
        const response = await fetch('/api/rent/history');
        if (!response.ok) {
          const errorText = await response.text();
          console.error('Failed to fetch rent data:', errorText);
          throw new Error(`Network response was not ok: ${response.statusText}`);
        }
        const data = await response.json();
        
        if (data && data.length > 0) {
          setRentData(data[data.length - 1].final_results);
        } else {
          setRentData(null); // No data available
        }
      } catch (err) {
        setError(err instanceof Error ? err.message : 'An unknown error occurred');
      } finally {
        setIsLoading(false);
      }
    };

    fetchRentData();
  }, []);

  if (isLoading) {
    return (
      <div className="p-6 bg-white rounded-xl shadow-md flex items-center justify-center h-64">
        <p className="text-slate-500">Loading rent data...</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="p-6 bg-red-50 text-red-700 rounded-xl shadow-md">
        <div className="flex items-center gap-3">
          <AlertCircle className="h-6 w-6" />
          <h3 className="text-lg font-semibold">Error Loading Rent Data</h3>
        </div>
        <p className="mt-2 text-sm">{error}</p>
      </div>
    );
  }

  if (!rentData) {
    return (
      <div className="p-6 bg-white rounded-xl shadow-md">
        <h3 className="text-lg font-semibold text-slate-800">Monthly Rent Summary</h3>
        <p className="mt-2 text-slate-500">No rent data is available for the current period.</p>
      </div>
    );
  }

  return (
    <div className="p-6 bg-white rounded-xl shadow-md">
      <div className="flex justify-between items-start mb-4">
        <h2 className="text-xl font-bold text-slate-800">Monthly Rent Summary</h2>
        <span className="text-sm font-medium text-slate-500">July 2025</span>
      </div>
      
      <div className="mb-6">
        <p className="text-sm text-slate-500 mb-1">Total Rent</p>
        <p className="text-4xl font-extrabold text-slate-900">{rentData.Total.toLocaleString('sv-SE')} kr</p>
      </div>

      <div>
        <h3 className="text-md font-semibold mb-3 text-slate-700">Rent per Roommate</h3>
        <ul className="space-y-3">
          {Object.entries(rentData['Rent per Roommate']).map(([name, amount]) => (
            <li key={name} className="flex justify-between items-center bg-slate-50 p-4 rounded-lg">
              <span className="font-medium text-slate-800">{name}</span>
              <span className="font-mono text-slate-900 font-semibold">{amount.toLocaleString('sv-SE')} kr</span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
};

export default RentPanel; 