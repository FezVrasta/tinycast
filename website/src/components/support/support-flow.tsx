"use client";

import { useEffect, useSyncExternalStore, type ReactNode } from "react";
import type { Plan } from "../../data/support";
import { CheckoutCard } from "./checkout-card";
import { ThankYou } from "./thank-you";

const THANKS_PARAM = "thanks";

// Read once and kept: the URL is cleaned right after, and a reload must not thank them twice.
let returnedPlan: Plan | null | undefined;

function readReturnedPlan(): Plan | null {
  if (returnedPlan === undefined) {
    const value = new URLSearchParams(window.location.search).get(THANKS_PARAM);
    returnedPlan = value === "monthly" || value === "one-time" ? value : null;
  }
  return returnedPlan;
}

function subscribeNever(): () => void {
  return () => {};
}

type Props = {
  intro: ReactNode;
  reasons: ReactNode;
};

/** `intro` and `reasons` are server-rendered and passed through, so only the card ships as JS. */
export function SupportFlow({ intro, reasons }: Props) {
  // After paying, Polar sends the visitor back here with ?thanks=<plan>.
  const returned = useSyncExternalStore(
    subscribeNever,
    readReturnedPlan,
    () => null,
  );

  useEffect(() => {
    if (!returned) return;
    const url = new URL(window.location.href);
    url.searchParams.delete(THANKS_PARAM);
    window.history.replaceState(window.history.state, "", url);
  }, [returned]);

  // Phones read intro → card → reasons; from lg the card holds the right column beside both.
  return (
    <div className="grid gap-10 lg:grid-cols-[minmax(0,1fr)_420px] lg:gap-x-20 lg:gap-y-14">
      {intro}
      <div className="relative lg:col-start-2 lg:row-span-2 lg:row-start-1">
        <span
          aria-hidden="true"
          className="mark-bloom pointer-events-none absolute inset-x-0 -top-16 h-72 opacity-60"
        />
        <div className="relative lg:sticky lg:top-20">
          {returned ? <ThankYou plan={returned} /> : <CheckoutCard />}
        </div>
      </div>
      {reasons}
    </div>
  );
}
