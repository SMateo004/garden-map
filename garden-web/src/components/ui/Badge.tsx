import { type ReactNode } from 'react';

interface BadgeProps {
  children: ReactNode;
  variant?: 'default' | 'verified' | 'muted';
  className?: string;
}

export function Badge({ children, variant = 'default', className = '' }: BadgeProps) {
  const base = 'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium';
  const variants = {
    default: 'bg-gray-100 text-gray-800',
    verified: 'bg-green-100 text-green-800',
    muted: 'bg-gray-50 text-gray-500',
  };
  return <span className={`${base} ${variants[variant]} ${className}`}>{children}</span>;
}
