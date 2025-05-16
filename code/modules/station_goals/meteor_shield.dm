/// number of emagged meteor shields to get the first warning, a simple say message
#define EMAGGED_METEOR_SHIELD_THRESHOLD_ONE 3
/// number of emagged meteor shields to get the second warning, telling the user an announcement is coming
#define EMAGGED_METEOR_SHIELD_THRESHOLD_TWO 6
/// number of emagged meteor shields to get the third warning + an announcement to the crew
#define EMAGGED_METEOR_SHIELD_THRESHOLD_THREE 7
/// number of emagged meteor shields to get the fourth... ah shit the dark matt-eor is coming.
#define EMAGGED_METEOR_SHIELD_THRESHOLD_FOUR 10
/// how long between emagging meteor shields you have to wait
#define METEOR_SHIELD_EMAG_COOLDOWN 1 MINUTES

/datum/station_goal/station_shield
	name = "Station Shield"
	requires_space = TRUE
	var/coverage_goal = 50
	VAR_PRIVATE/cached_coverage_length

/datum/station_goal/station_shield/get_report()
	return list(
		"#### Система противометеорной защиты",
		"Станция находится в зоне, заполненной космическим мусором.",
		"У вас есть прототип защитной системы, который необходимо развернуть для снижения количества аварий из-за столкновений.<br>",
		"Вы можете заказать спутники и системы через отдел снабжения.",
		"Требуется: [cached_coverage_length]/[coverage_goal] единиц покрытия (1 спутник = 10 единиц)"
	).Join("\n")

/datum/station_goal/station_shield/on_report()
	var/datum/supply_pack/P = SSshuttle.supply_packs[/datum/supply_pack/engineering/shield_sat]
	P.special_enabled = TRUE
	P = SSshuttle.supply_packs[/datum/supply_pack/engineering/shield_sat_control]
	P.special_enabled = TRUE

/datum/station_goal/station_shield/check_completion()
	if(..())
		return TRUE
	update_coverage()
	return cached_coverage_length >= coverage_goal

/datum/station_goal/station_shield/proc/update_coverage()
	var/active_shields = 0
	for(var/obj/machinery/satellite/meteor_shield/shield_satt in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/satellite/meteor_shield))
		if(shield_satt.active && is_station_level(shield_satt.z))
			active_shields++
	cached_coverage_length = active_shields * 10

/obj/machinery/satellite/meteor_shield
	name = "\improper Meteor Shield Satellite"
	desc = "A meteor point-defense satellite."
	mode = "M-SHIELD"
	var/kill_range = 14
	var/datum/proximity_monitor/proximity_monitor
	var/static/emagged_active_meteor_shields = 0
	var/static/highest_emagged_threshold_reached = 0
	STATIC_COOLDOWN_DECLARE(shared_emag_cooldown)

/obj/machinery/satellite/meteor_shield/examine(mob/user)
	. = ..()
	. += span_info("Требуется минимальное расстояние в 10 тайлов между активными спутниками.")
	if(active)
		if(obj_flags & EMAGGED)
			. += span_warning("Излучает странный шипящий звук...")
	else
		if(obj_flags & EMAGGED)
			. += span_warning("Кажется, система защиты отключена...")

/obj/machinery/satellite/meteor_shield/Initialize(mapload)
	. = ..()
	proximity_monitor = new(src, 0)

/obj/machinery/satellite/meteor_shield/HasProximity(atom/movable/proximity_check_mob)
	if(!istype(proximity_check_mob, /obj/effect/meteor))
		return
	var/obj/effect/meteor/M = proximity_check_mob
	if(space_los(M))
		var/turf/beam_from = get_turf(src)
		beam_from.Beam(get_turf(M), icon_state="sat_beam", time = 5)
		if(M.shield_defense(src))
			qdel(M)

/obj/machinery/satellite/meteor_shield/proc/space_los(meteor)
	for(var/turf/T in get_line(src, meteor))
		if(!isspaceturf(T))
			return FALSE
	return TRUE

/obj/machinery/satellite/meteor_shield/toggle(user)
	if(user)
		balloon_alert(user, "looking for [active ? "off" : "on"] button")
	if(user && !do_after(user, 2 SECONDS, src))
		return FALSE

	if(!active)
		var/list/activation_check = can_activate()
		if(!activation_check[1])
			if(user)
				to_chat(user, span_warning("Нельзя активировать: [activation_check[2]]"))
			return FALSE

	if(!..())
		return FALSE

	if(obj_flags & EMAGGED)
		update_emagged_meteor_sat(user)

	proximity_monitor.set_range(active ? kill_range : 0)
	var/datum/station_goal/station_shield/goal = SSstation.get_station_goal(/datum/station_goal/station_shield)
	goal?.update_coverage()
	return TRUE

/obj/machinery/satellite/meteor_shield/proc/can_activate()
	var/list/conflicting = list()
	for(var/obj/machinery/satellite/meteor_shield/other in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/satellite/meteor_shield))
		if(other == src || !other.active || other.z != z)
			continue
		var/distance = sqrt((x - other.x)**2 + (y - other.y)**2)
		if(distance < 10)
			conflicting += other

	if(length(conflicting))
		var/msg = "Конфликтующие спутники:"
		for(var/obj/machinery/satellite/M in conflicting)
			msg += "\n-[M] в ([M.x], [M.y])"
		return list(FALSE, msg)

	return list(TRUE, "")

/obj/machinery/satellite/meteor_shield/Destroy()
	QDEL_NULL(proximity_monitor)
	if(obj_flags & EMAGGED && active)
		update_emagged_meteor_sat()
	return ..()

/obj/machinery/satellite/meteor_shield/emag_act(mob/user, obj/item/card/emag/emag_card)
	if(obj_flags & EMAGGED)
		balloon_alert(user, "Уже эмэггнуто!")
		return FALSE
	if(!COOLDOWN_FINISHED(src, shared_emag_cooldown))
		balloon_alert(user, "Перезарядка!")
		to_chat(user, span_warning("Требуется [DisplayTimeText(COOLDOWN_TIMELEFT(src, shared_emag_cooldown))] перед следующим эмэггингом."))
		return FALSE

	COOLDOWN_START(src, shared_emag_cooldown, METEOR_SHIELD_EMAG_COOLDOWN)
	obj_flags |= EMAGGED
	to_chat(user, span_notice("Активирован режим привлечения метеоров!"))
	AddComponent(/datum/component/gps, "Искажённый сигнал")
	say("Калибровка... [DisplayTimeText(METEOR_SHIELD_EMAG_COOLDOWN)]")

	if(active)
		update_emagged_meteor_sat(user)
	return TRUE

/obj/machinery/satellite/meteor_shield/proc/update_emagged_meteor_sat(mob/user)
	if(!active)
		change_meteor_chance(0.5)
		emagged_active_meteor_shields--
		if(user)
			balloon_alert(user, "Шанс метеоров уменьшен")
		return

	change_meteor_chance(2)
	emagged_active_meteor_shields++
	if(user)
		balloon_alert(user, "Шанс метеоров увеличен")

	if(emagged_active_meteor_shields > highest_emagged_threshold_reached)
		highest_emagged_threshold_reached = emagged_active_meteor_shields
		handle_new_emagged_shield_threshold()

/obj/machinery/satellite/meteor_shield/proc/handle_new_emagged_shield_threshold()
	switch(highest_emagged_threshold_reached)
		if(EMAGGED_METEOR_SHIELD_THRESHOLD_ONE)
			say("Внимание: повышен риск экзотических метеоров")
		if(EMAGGED_METEOR_SHIELD_THRESHOLD_TWO)
			say("Опасность: возможна конденсация тёмной материи")
		if(EMAGGED_METEOR_SHIELD_THRESHOLD_THREE)
			say("Обнаружено вмешательство! Отправлен отчет.")
			priority_announce("ВНИМАНИЕ: Обнаружено вмешательство в метеорные щиты. Проверьте GPS сигналы.", "Служба безопасности")
		if(EMAGGED_METEOR_SHIELD_THRESHOLD_FOUR)
			say("КРИТИЧЕСКИЙ СБОЙ! Тёмный метеор на курсе!")
			force_event_async(/datum/round_event_control/dark_matteor, "взломанные спутники")

/obj/machinery/satellite/meteor_shield/proc/change_meteor_chance(mod)
	for(var/datum/round_event_control/meteor_wave/meteors in SSevents.control)
		meteors.weight *= mod
	for(var/datum/round_event_control/stray_meteor/stray in SSevents.control)
		stray.weight *= mod

#undef EMAGGED_METEOR_SHIELD_THRESHOLD_ONE
#undef EMAGGED_METEOR_SHIELD_THRESHOLD_TWO
#undef EMAGGED_METEOR_SHIELD_THRESHOLD_THREE
#undef EMAGGED_METEOR_SHIELD_THRESHOLD_FOUR
#undef METEOR_SHIELD_EMAG_COOLDOWN
