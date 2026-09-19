# Remotes - Guess the Puncher
## Exact Setup for ReplicatedStorage/Remotes

Create a Folder named `Remotes` in `ReplicatedStorage`.

Inside it, create **20 RemoteEvents** with these EXACT names (case-sensitive):

1. `RE_SlotJoinRequest` - Client -> Server - (slotId: string)
2. `RE_SlotLeaveRequest` - Client -> Server - ()
3. `RE_SlotStateUpdate` - Server -> All Clients - (slotId, occupancy: {userId}, maxPlayers: number, countdownActive: bool, countdownTimeLeft: number)
4. `RE_MatchCountdownUpdate` - Server -> Clients in Slot - (slotId, timeLeft: number)
5. `RE_MatchStart` - Server -> Clients in Match - (matchId, arenaName, players: {userId})
6. `RE_MatchStateUpdate` - Server -> Clients in Match - (payload table: matchId, state, targetUserId?, alivePlayers, healthTable, puncherUserId? filtered)
7. `RE_PunchOpportunityOpen` - Server -> Clients in Match (except Target) - (matchId, windowDuration)
8. `RE_PunchRequest` - Client -> Server - (matchId)
9. `RE_PuncherSelected` - Server -> Clients in Match - (matchId, puncherUserId, targetUserId) **FILTERED: Target client gets puncherUserId = nil**
10. `RE_PowerGaugeOpen` - Server -> Puncher Client Only - (matchId)
11. `RE_PowerGaugeStopRequest` - Client -> Server - (matchId)
12. `RE_PowerGaugeResult` - Server -> Clients in Match - (matchId, puncherUserId, powerTier, damage)
13. `RE_DamageApplied` - Server -> Clients in Match - (matchId, targetUserId, newHealth, isKO)
14. `RE_GuessOpen` - Server -> Target Client Only - (matchId, guessablePlayers: {userId})
15. `RE_GuessRequest` - Client -> Server - (matchId, guessedUserId)
16. `RE_GuessResult` - Server -> Clients in Match - (matchId, correct, guessedUserId, actualPuncherUserId, nextTargetUserId?)
17. `RE_TargetEliminated` - Server -> Clients in Match - (matchId, eliminatedUserId)
18. `RE_MatchEnd` - Server -> Clients in Match - (matchId, winnerUserId)
19. `RE_CameraMode` - Server -> Individual Client - (mode: string)
20. `RE_AnimationPlay` - Server -> Clients in Match - (userId, animType, powerTier?)

## How to create:
1. In Explorer, right-click ReplicatedStorage -> Insert Object -> Folder -> Name `Remotes`
2. Right-click Remotes -> Insert Object -> RemoteEvent -> Name exactly `RE_SlotJoinRequest`
3. Repeat for all 20.
4. Ensure they are RemoteEvent, not RemoteFunction, not BindableEvent.

## Security Notes:
- Server must validate every Client->Server remote (SlotJoin, SlotLeave, PunchRequest, PowerGaugeStopRequest, GuessRequest) with player.UserId, never trust client-provided UserId.
- Puncher identity must be filtered: never send puncherUserId to Target client during GUESSING phase. Implementation will have function `getFilteredPayloadForPlayer(player)` in MatchService.
- PowerGaugeStopRequest: client sends only matchId, server calculates power from server tick, never trusts client power.
- All Server->Client remotes that include matchId must check player's current matchId.

## Phase 1 Validation:
- Server Main.server.luau will print warning listing any missing remotes.
- Client Main.client.luau will also warn.

## Future Consolidation:
- If you want fewer remotes, you can merge MatchCountdownUpdate into SlotStateUpdate, but keep names as constants for now. Phase 1 requires all 20 to exist even if not used yet.
