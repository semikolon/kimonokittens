import React, { useState, useEffect } from 'react';
import { TrendingUp, TrendingDown, AlertCircle, HelpCircle, Users, Home, Zap, Droplet } from 'lucide-react';

// Enhanced interface to match the actual data structure from the backend
interface RentDetails {
  total: number;
  rent_per_roommate: { [name: string]: number };
  // Add other potential fields from the backend for a more detailed view
  config: {
    kallhyra: number;
    el: number;
    bredband: number;
    vattenavgift: number;
    larm: number;
    [key: string]: any; // Allow for other config values
  };
  roommates: {
    [name: string]: {
      days: number;
      room_adjustment: number;
    }
  }
}

// Represents a single record from the /api/rent/history array
interface RentHistoryRecord {
  // Assuming 'final_results' is the key holding the detailed data
  final_results: RentDetails;
  // Other potential fields in the record
  title: string;
  created_at: string;
}


const StatCard: React.FC<{ icon: React.ReactNode; label: string; value: string; subtext?: string }> = ({ icon, label, value, subtext }) => (
  <div className="bg-slate-50 p-4 rounded-lg flex items-center">
    <div className="bg-slate-200 text-slate-600 p-3 rounded-full mr-4">
      {icon}
    </div>
    <div>
      <p className="text-sm font-medium text-slate-500">{label}</p>
      <p className="text-xl font-bold text-slate-800">{value}</p>
      {subtext && <p className="text-xs text-slate-400">{subtext}</p>}
    </div>
  </div>
);


const RentPanel: React.FC = () => {
  const [rentDetails, setRentDetails] = useState<RentDetails | null>(null);
  const [rentTitle, setRentTitle] = useState<string>('Latest Calculation');
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchRentData = async () => {
      // Per user instruction, we are in July 2025
      const now = new Date('2025-07-04T12:00:00Z');
      const year = now.getFullYear();
      const month = now.getMonth() + 1;

      try {
        // Step 1: Try to fetch historical data for the current month
        let response = await fetch(`/api/rent/history?year=${year}&month=${month}`);
        let data: RentHistoryRecord[] = await response.json();

        // Step 2: If no data, fetch a forecast
        if (!response.ok || data.length === 0) {
          response = await fetch(`/api/rent/forecast?year=${year}&month=${month}`);
          if (!response.ok) {
            const errorText = await response.text();
            console.error('Failed to fetch rent forecast:', errorText);
            throw new Error(`Network response was not ok for forecast: ${errorText || response.statusText}`);
          }
          data = [await response.json()]; // Wrap forecast in array to match history structure
        }
        
        // Use the most recent entry from the history or the forecast
        if (data && data.length > 0) {
          const latestRecord = data[data.length - 1];
          setRentDetails(latestRecord.final_results);
          setRentTitle(latestRecord.title || 'Latest Calculation');
        } else {
          setRentDetails(null); // No data available
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
      <div className="p-6 bg-white rounded-xl shadow-md flex items-center justify-center h-80 animate-pulse">
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

  if (!rentDetails) {
    return (
      <div className="p-6 bg-white rounded-xl shadow-md">
        <div className="flex items-center gap-3">
            <HelpCircle className="h-6 w-6 text-slate-400" />
            <h3 className="text-lg font-semibold text-slate-800">No Rent Data Available</h3>
        </div>
        <p className="mt-2 text-slate-500">There is no rent calculation data available for the current period.</p>
      </div>
    );
  }
  
  const { total, rent_per_roommate, config, roommates } = rentDetails;

  return (
    <div className="p-6 bg-white rounded-xl shadow-md">
      <div className="flex justify-between items-start mb-6">
        <div>
          <h2 className="text-xl font-bold text-slate-800">Monthly Rent Summary</h2>
          <p className="text-sm text-slate-500">{rentTitle}</p>
        </div>
        <div className='text-right'>
            <p className="text-sm text-slate-500 mb-1">Total</p>
            <p className="text-3xl font-extrabold text-slate-900">{(total ?? 0).toLocaleString('sv-SE')} kr</p>
        </div>
      </div>
      
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        <StatCard icon={<Home size={20} />} label="Base Rent" value={`${(config?.kallhyra ?? 0).toLocaleString('sv-SE')} kr`} />
        <StatCard icon={<Zap size={20} />} label="Electricity" value={`${(config?.el ?? 0).toLocaleString('sv-SE')} kr`} />
        <StatCard icon={<Droplet size={20} />} label="Water/Fees" value={`${((config?.vattenavgift ?? 0) + (config?.va ?? 0)).toLocaleString('sv-SE')} kr`} />
        <StatCard icon={<Users size={20} />} label="Tenants" value={`${Object.keys(rent_per_roommate ?? {}).length}`} />
      </div>

      <div>
        <h3 className="text-md font-semibold mb-3 text-slate-700">Rent per Roommate</h3>
        <ul className="space-y-3">
          {Object.entries(rent_per_roommate ?? {}).map(([name, amount]) => {
            const adjustment = roommates?.[name]?.room_adjustment ?? 0;
            return (
              <li key={name} className="flex justify-between items-center bg-slate-50 hover:bg-slate-100 transition-colors p-4 rounded-lg">
                <div className="flex flex-col">
                  <span className="font-medium text-slate-800">{name}</span>
                  {adjustment !== 0 && (
                     <div className="flex items-center text-xs">
                       {adjustment > 0 ? <TrendingUp className="h-3 w-3 mr-1 text-green-500" /> : <TrendingDown className="h-3 w-3 mr-1 text-red-500" />}
                       <span className={adjustment > 0 ? 'text-green-600' : 'text-red-600'}>
                         Adjustment: {adjustment.toLocaleString('sv-se')} kr
                       </span>
                     </div>
                  )}
                </div>
                <span className="font-mono text-slate-900 font-semibold text-lg">{(amount ?? 0).toLocaleString('sv-SE')} kr</span>
              </li>
            )
          })}
        </ul>
      </div>
    </div>
  );
};

export default RentPanel; 