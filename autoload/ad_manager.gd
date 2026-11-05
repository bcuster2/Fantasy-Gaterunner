extends Node
## Ads facade. Every ad in the game goes through here, so the rest of the code never touches the
## SDK. Milestone 9 wires in AdMob (Poing Studios plugin), consent, and interstitial pacing.
## Until then: dev builds simulate successful rewarded ads (so retry/revive flows are testable),
## release builds report "not available", and the game always works without ads.

signal rewarded_finished(placement: String, rewarded: bool)


func is_rewarded_available(_placement: String) -> bool:
	return OS.is_debug_build()


## Shows a rewarded ad; calls on_reward only if the player earned it, otherwise on_fail (if given).
func show_rewarded(placement: String, on_reward: Callable, on_fail: Callable = Callable()) -> void:
	if OS.is_debug_build():
		print("[ads] simulated rewarded ad: %s" % placement)
		rewarded_finished.emit(placement, true)
		on_reward.call()
		return
	rewarded_finished.emit(placement, false)
	if on_fail.is_valid():
		on_fail.call()


## Interstitial opportunity after a completed run (pacing rules arrive in Milestone 9).
func on_run_completed() -> void:
	pass
