import Img from "next/image";
import Link from "next/link";
import React from "react";
import { fromWei } from "web3-utils"; // Importing directly is more efficient

interface MarketCardProps {
  id: string;
  title: string;
  totalAmount: string;
  totalYes: string;
  totalNo: string;
  imageHash: string;
}

export const MarketCard: React.FC<MarketCardProps> = ({
  id,
  title,
  totalAmount,
  totalYes,
  totalNo,
  imageHash,
}) => {
  // Use a reliable public gateway if you don't have a dedicated Infura sub-domain
  const imageUrl = `https://ipfs.io/ipfs/${imageHash}`;

  return (
    <div className="w-full px-2 my-4 sm:w-1/2 lg:w-1/3">
      <Link href={`/market/${id}`} className="block group">
        <div className="flex flex-col border border-gray-200 rounded-xl p-5 bg-white shadow-sm transition-all hover:shadow-md hover:border-blue-500">
          
          {/* Header: Image and Title */}
          <div className="flex items-start space-x-4 mb-6">
            <div className="relative w-14 h-14 flex-shrink-0">
              <Img
                src={imageUrl}
                alt={title}
                fill
                className="rounded-full object-cover border border-gray-100"
                sizes="56px"
              />
            </div>
            <h3 className="text-lg font-semibold text-gray-800 line-clamp-2 leading-tight group-hover:text-blue-600">
              {title}
            </h3>
          </div>

          {/* Statistics Grid */}
          <div className="grid grid-cols-3 gap-2 pt-4 border-t border-gray-50">
            <StatItem label="Volume" value={fromWei(totalAmount, "ether")} color="text-gray-900" />
            <StatItem label="Yes" value={fromWei(totalYes, "ether")} color="text-green-600" isBadge />
            <StatItem label="No" value={fromWei(totalNo, "ether")} color="text-red-600" isBadge />
          </div>
        </div>
      </Link>
    </div>
  );
};


const StatItem = ({ label, value, color, isBadge }: any) => (
  <div className="flex flex-col">
    <span className="text-[10px] uppercase tracking-wider text-gray-400 font-bold mb-1">{label}</span>
    <div className={`${isBadge ? 'bg-gray-50 px-2 py-1 rounded-md' : ''}`}>
      <span className={`text-sm font-bold ${color}`}>
        {parseFloat(value).toFixed(2)} <span className="text-[10px] font-normal">POLY</span>
      </span>
    </div>
  </div>
);