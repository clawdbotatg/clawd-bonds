"use client";

import { useEffect, useState } from "react";
import { Address } from "@scaffold-ui/components";
import type { NextPage } from "next";
import { formatEther, parseEther } from "viem";
import { base } from "viem/chains";
import { useAccount, useChainId, useSwitchChain } from "wagmi";
import { RainbowKitCustomConnectButton } from "~~/components/scaffold-eth";
import { useDeployedContractInfo, useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";
import { notification } from "~~/utils/scaffold-eth";

// ── helpers ──────────────────────────────────────────────

const fmtClawd = (wei: bigint) => {
  const num = Number(formatEther(wei));
  return num.toLocaleString(undefined, { maximumFractionDigits: 0 });
};

const formatTimeRemaining = (maturityTs: bigint): string => {
  const remaining = Number(maturityTs) - Math.floor(Date.now() / 1000);
  if (remaining <= 0) return "Matured ✅";
  const d = Math.floor(remaining / 86400);
  const h = Math.floor((remaining % 86400) / 3600);
  const m = Math.floor((remaining % 3600) / 60);
  if (d > 0) return `${d}d ${h}h ${m}m`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
};

// ── Bond Card ────────────────────────────────────────────

const BondCard = ({ bondId }: { bondId: bigint }) => {
  const [timeLeft, setTimeLeft] = useState("");
  const [isClaiming, setIsClaiming] = useState(false);

  const { data: bond } = useScaffoldReadContract({
    contractName: "ClaWDBonds",
    functionName: "getBond",
    args: [bondId],
  });

  const { data: claimable } = useScaffoldReadContract({
    contractName: "ClaWDBonds",
    functionName: "isBondClaimable",
    args: [bondId],
  });

  const { writeContractAsync: writeBonds } = useScaffoldWriteContract("ClaWDBonds");

  useEffect(() => {
    if (!bond) return;
    const update = () => setTimeLeft(formatTimeRemaining(bond.maturityTimestamp));
    update();
    const iv = setInterval(update, 30_000);
    return () => clearInterval(iv);
  }, [bond]);

  if (!bond || bond.user === "0x0000000000000000000000000000000000000000") return null;

  const matured = claimable === true;

  return (
    <div className={`card bg-base-200 shadow-md ${matured ? "border-2 border-success" : ""}`}>
      <div className="card-body p-4">
        <div className="flex justify-between items-center">
          <span className="font-bold">Bond #{bondId.toString()}</span>
          <span className={`badge ${bond.claimed ? "badge-ghost" : matured ? "badge-success" : "badge-info"}`}>
            {bond.claimed ? "Claimed" : matured ? "Ready" : "Active"}
          </span>
        </div>
        <div className="grid grid-cols-2 gap-1 text-sm mt-2">
          <span className="opacity-70">Locked:</span>
          <span className="text-right">{fmtClawd(bond.amount)} CLAWD</span>
          <span className="opacity-70">Reward:</span>
          <span className="text-right text-success">+{fmtClawd(bond.reward)} CLAWD</span>
          <span className="opacity-70">Payout:</span>
          <span className="text-right font-semibold">{fmtClawd(bond.amount + bond.reward)} CLAWD</span>
          {!bond.claimed && (
            <>
              <span className="opacity-70">Time:</span>
              <span className="text-right">{timeLeft}</span>
            </>
          )}
        </div>
        {matured && !bond.claimed && (
          <button
            className="btn btn-success btn-sm mt-2"
            disabled={isClaiming}
            onClick={async () => {
              setIsClaiming(true);
              try {
                await writeBonds({ functionName: "claimBond", args: [bondId] });
                notification.success(`Claimed bond #${bondId}!`);
              } catch {
                notification.error("Claim failed");
              } finally {
                setIsClaiming(false);
              }
            }}
          >
            {isClaiming ? "Claiming..." : "Claim Bond"}
          </button>
        )}
      </div>
    </div>
  );
};

// ── Main Page ────────────────────────────────────────────

const Home: NextPage = () => {
  const { address } = useAccount();
  const chainId = useChainId();
  const { switchChain } = useSwitchChain();
  const [bondAmount, setBondAmount] = useState("");
  const [selectedTerm, setSelectedTerm] = useState<number>(0);
  const [isApproving, setIsApproving] = useState(false);
  const [isCreating, setIsCreating] = useState(false);
  const [isSwitching, setIsSwitching] = useState(false);
  const wrongNetwork = !!address && chainId !== base.id;

  const { data: bondsContract } = useDeployedContractInfo("ClaWDBonds");
  const contractAddr = bondsContract?.address;

  // ── reads ──
  const { data: stats } = useScaffoldReadContract({
    contractName: "ClaWDBonds",
    functionName: "getContractStats",
  });

  const { data: term0 } = useScaffoldReadContract({
    contractName: "ClaWDBonds",
    functionName: "getBondTerm",
    args: [0],
  });

  const { data: term1 } = useScaffoldReadContract({
    contractName: "ClaWDBonds",
    functionName: "getBondTerm",
    args: [1],
  });

  const { data: clawdBalance } = useScaffoldReadContract({
    contractName: "CLAWD",
    functionName: "balanceOf",
    args: [address],
  });

  const { data: allowance } = useScaffoldReadContract({
    contractName: "CLAWD",
    functionName: "allowance",
    args: [address, contractAddr],
  });

  const { data: userBondIds } = useScaffoldReadContract({
    contractName: "ClaWDBonds",
    functionName: "getUserBonds",
    args: [address],
  });

  // ── writes ──
  const { writeContractAsync: writeApprove } = useScaffoldWriteContract("CLAWD");
  const { writeContractAsync: writeBonds } = useScaffoldWriteContract("ClaWDBonds");

  // ── derived ──
  const parsedAmt = bondAmount ? parseEther(bondAmount) : 0n;
  const needsApproval = parsedAmt > 0n && (!allowance || allowance < parsedAmt);
  const notConnected = !address;

  const terms = [term0, term1];
  const termLabels = ["24 Hours", "7 Days"];
  const termRates = ["0.5%", "2%"];

  // ── handlers ──
  const handleApprove = async () => {
    if (!contractAddr) return;
    setIsApproving(true);
    try {
      await writeApprove({ functionName: "approve", args: [contractAddr, parsedAmt] });
      notification.success("Approved!");
    } catch {
      notification.error("Approval failed");
    } finally {
      setIsApproving(false);
    }
  };

  const handleCreateBond = async () => {
    setIsCreating(true);
    try {
      await writeBonds({ functionName: "createBond", args: [parsedAmt, selectedTerm] });
      notification.success("Bond created!");
      setBondAmount("");
    } catch {
      notification.error("Bond creation failed");
    } finally {
      setIsCreating(false);
    }
  };

  return (
    <div className="flex flex-col items-center gap-6 p-4 max-w-3xl mx-auto">
      {/* Treasury Stats */}
      <div className="w-full card bg-base-100 shadow-xl">
        <div className="card-body">
          <h2 className="card-title">🏦 Treasury</h2>
          {stats ? (
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div>
                <div className="text-xs opacity-70">Total Funded</div>
                <div className="font-bold">{fmtClawd(stats[0])}</div>
              </div>
              <div>
                <div className="text-xs opacity-70">Available</div>
                <div className="font-bold text-success">{fmtClawd(stats[1])}</div>
              </div>
              <div>
                <div className="text-xs opacity-70">Committed</div>
                <div className="font-bold text-warning">{fmtClawd(stats[2])}</div>
              </div>
              <div>
                <div className="text-xs opacity-70">Total Bonds</div>
                <div className="font-bold">{stats[3].toString()}</div>
              </div>
            </div>
          ) : (
            <div className="text-sm opacity-50">Loading...</div>
          )}
        </div>
      </div>

      {/* Bond Terms + Create */}
      <div className="w-full card bg-base-100 shadow-xl">
        <div className="card-body">
          <h2 className="card-title">🔒 Create Bond</h2>

          {/* Term Selector */}
          <div className="grid grid-cols-2 gap-3 mt-2">
            {terms.map((term, i) =>
              term ? (
                <div
                  key={i}
                  className={`card cursor-pointer border-2 transition-all ${
                    selectedTerm === i ? "border-primary bg-primary/10" : "border-base-300 hover:border-primary/50"
                  }`}
                  onClick={() => setSelectedTerm(i)}
                >
                  <div className="card-body p-3 text-center">
                    <div className="font-bold">{termLabels[i]}</div>
                    <div className="text-success text-lg">{termRates[i]} reward</div>
                  </div>
                </div>
              ) : null,
            )}
          </div>

          {/* Amount Input */}
          <div className="form-control mt-4">
            <label className="label">
              <span className="label-text">Amount (CLAWD)</span>
              {clawdBalance !== undefined && (
                <span
                  className="label-text-alt cursor-pointer hover:underline"
                  onClick={() => setBondAmount(formatEther(clawdBalance))}
                >
                  Balance: {fmtClawd(clawdBalance)}
                </span>
              )}
            </label>
            <input
              type="number"
              className="input input-bordered"
              placeholder="100000"
              value={bondAmount}
              onChange={e => setBondAmount(e.target.value)}
              min="0"
            />
            {parsedAmt > 0n && (
              <div className="text-xs mt-1 opacity-60">
                Reward: +{fmtClawd((parsedAmt * BigInt(selectedTerm === 0 ? 50 : 200)) / 10000n)} CLAWD
              </div>
            )}
          </div>

          {/* Four-State Flow: Connect → Network → Approve → Action */}
          <div className="mt-4">
            {notConnected ? (
              <RainbowKitCustomConnectButton />
            ) : wrongNetwork ? (
              <button
                className="btn btn-warning w-full"
                disabled={isSwitching}
                onClick={async () => {
                  setIsSwitching(true);
                  try {
                    await switchChain({ chainId: base.id });
                  } catch {
                    notification.error("Failed to switch network");
                  } finally {
                    setIsSwitching(false);
                  }
                }}
              >
                {isSwitching ? "Switching..." : "Switch to Base"}
              </button>
            ) : needsApproval ? (
              <button
                className="btn btn-primary w-full"
                disabled={isApproving || parsedAmt === 0n}
                onClick={handleApprove}
              >
                {isApproving ? "Approving..." : "Approve CLAWD"}
              </button>
            ) : (
              <button
                className="btn btn-primary w-full"
                disabled={isCreating || parsedAmt === 0n}
                onClick={handleCreateBond}
              >
                {isCreating ? "Creating Bond..." : `Bond for ${termLabels[selectedTerm]}`}
              </button>
            )}
          </div>
        </div>
      </div>

      {/* My Bonds */}
      <div className="w-full card bg-base-100 shadow-xl">
        <div className="card-body">
          <h2 className="card-title">📋 My Bonds</h2>
          {!address ? (
            <div className="text-sm opacity-50">Connect wallet to view bonds</div>
          ) : !userBondIds || userBondIds.length === 0 ? (
            <div className="text-sm opacity-50">No bonds yet — create one above!</div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              {[...userBondIds].reverse().map(id => (
                <BondCard key={id.toString()} bondId={id} />
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Contract Address */}
      {contractAddr && (
        <div className="text-center text-sm opacity-70 pb-4">
          <p>Contract:</p>
          <Address address={contractAddr} />
        </div>
      )}
    </div>
  );
};

export default Home;
