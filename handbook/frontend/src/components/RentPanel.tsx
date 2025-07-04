import React, { useState, useEffect } from 'react';

interface RentData {
  // Define the structure of the rent data we expect from the API
  // This is a placeholder and should be updated to match the actual API response
  total: number;
  rentPerRoommate: { [name: string]: number };
}

const RentPanel: React.FC = () => {
  const [rentData, setRentData] = useState<RentData | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchRentData = async () => {
      try {
        // We'll fetch the latest for the current month.
        // The handler currently fetches all history for a month, so we'll take the last entry.
        const response = await fetch('/api/rent/history');
        if (!response.ok) {
          throw new Error('Failed to fetch rent data');
        }
        const data = await response.json();
        
        // Assuming the API returns an array of calculations for the month,
        // we'll take the most recent one.
        if (data && data.length > 0) {
          // This assumes the last entry is the most recent, which our handler provides.
          // The structure of this object needs to match what the Ruby API sends.
          // We'll need to adjust this after seeing a real response.
          const latestCalculation = data[data.length - 1];
          setRentData(latestCalculation.final_results); // Placeholder for actual structure
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
    return <div className="p-4 bg-gray-100 rounded-lg">Loading rent data...</div>;
  }

  if (error) {
    return <div className="p-4 bg-red-100 text-red-700 rounded-lg">Error: {error}</div>;
  }

  if (!rentData) {
    return <div className="p-4 bg-gray-100 rounded-lg">No rent data available for this month.</div>;
  }

  return (
    <div className="p-6 bg-white rounded-xl shadow-md">
      <h2 className="text-2xl font-bold mb-4 text-gray-800">Monthly Rent Summary</h2>
      <div className="space-y-4">
        <div className="flex justify-between items-center text-lg">
          <span className="text-gray-600">Total Rent:</span>
          <span className="font-semibold text-gray-900">{rentData.total.toLocaleString()} kr</span>
        </div>
        <div>
          <h3 className="text-lg font-semibold mb-2 text-gray-700">Rent per Roommate:</h3>
          <ul className="space-y-2">
            {Object.entries(rentData.rentPerRoommate).map(([name, amount]) => (
              <li key={name} className="flex justify-between items-center bg-gray-50 p-3 rounded-md">
                <span>{name}</span>
                <span className="font-mono text-gray-800">{amount.toLocaleString()} kr</span>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
};

export default RentPanel; 