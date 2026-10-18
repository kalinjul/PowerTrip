package org.julakali.chargeahead.shared.core

import org.julakali.chargeahead.shared.domain.RoadLoad
import org.julakali.chargeahead.shared.domain.Route
import org.julakali.chargeahead.shared.domain.VehicleProfile
import org.julakali.powertrip.vehicle.ConsumptionModel as VehiclePhysics

/**
 * How much energy a stretch of a route costs.
 *
 * Everything is expressed against distance from the route's start, the same
 * frame [TripPlanner] plans in.
 */
interface ConsumptionModel {

    /** Energy for the stretch from [fromKm] to [toKm]; negative when it drops more than it costs. */
    fun energyKwh(route: Route, fromKm: Double, toKm: Double): Double

    /** The most energy drawn at any point between [fromKm] and [toKm], counted from [fromKm]; never below zero. */
    fun peakEnergyKwh(route: Route, fromKm: Double, toKm: Double): Double

    /** The distance from the start at which [availableKwh] runs out, starting at [fromKm]. */
    fun reachKm(route: Route, fromKm: Double, availableKwh: Double): Double
}

/** Distance times a fixed rate — what the app did before it knew anything about speed. */
class ConstantConsumption(private val kwhPer100Km: Double) : ConsumptionModel {

    override fun energyKwh(route: Route, fromKm: Double, toKm: Double): Double =
        (toKm - fromKm).coerceAtLeast(0.0) / 100.0 * kwhPer100Km

    override fun peakEnergyKwh(route: Route, fromKm: Double, toKm: Double): Double = energyKwh(route, fromKm, toKm)

    override fun reachKm(route: Route, fromKm: Double, availableKwh: Double): Double =
        fromKm + availableKwh.coerceAtLeast(0.0) / kwhPer100Km * 100.0
}

/**
 * Prices each stretch of the route from the car's road-load curve at that
 * stretch's speed and outside temperature, plus the metres it climbs and
 * drops. The driver's consumption is read as the WLTP figure: the curve is
 * scaled so the WLTP cycle reproduces it, at the cycle's 23 °C.
 */
class RoadLoadConsumption(vehicle: VehicleProfile) : ConsumptionModel {

    private val roadLoad = vehicle.roadLoad ?: genericRoadLoad(vehicle.consumptionKwhPer100Km)
    private val correction = vehicle.consumptionKwhPer100Km / roadLoad.wltpKwhPer100Km
    private val kwhPerMetreOfHeight = roadLoad.massKg * GRAVITY / JOULES_PER_KWH

    /** Battery energy per 100 km on level ground at a stretch averaging [speedKmh]; no [temperatureC] prices it at 23 °C. */
    fun kwhPer100KmAt(speedKmh: Double, temperatureC: Double? = null): Double =
        (wheelKwhPerKm(speedKmh, temperatureC) / efficiency(temperatureC) + overheadKwhPerKm(speedKmh, temperatureC)) * 100.0

    /** What the wheels have to push against road and air, per km; cold air is denser. */
    private fun wheelKwhPerKm(speedKmh: Double, temperatureC: Double?): Double {
        val speed = clamp(speedKmh)
        val denserAir = roadLoad.f2 * speed * speed * (airDensityFactor(temperatureC) - 1.0)
        return correction * (roadLoad.forceN(speed) + denserAir) * 1000.0 / JOULES_PER_KWH
    }

    private fun efficiency(temperatureC: Double?) = roadLoad.drivetrainEfficiency / coldLossFactor(temperatureC)

    private fun recuperation(temperatureC: Double?) = roadLoad.recuperationShare / coldLossFactor(temperatureC)

    /**
     * Auxiliaries and speed changes, per km; neither is offset by going
     * downhill. Heating and cooling are the same kilowatts in every car, so
     * the driver's figure does not scale them.
     */
    private fun overheadKwhPerKm(speedKmh: Double, temperatureC: Double?): Double {
        val speed = clamp(speedKmh)
        val auxiliary = roadLoad.auxiliaryPowerKw / speed
        val acceleration = VehiclePhysics.ROTATING_MASS_FACTOR * roadLoad.massKg * kineticJoulesPerKgAndMetre(speed) *
            (1.0 / efficiency(temperatureC) - recuperation(temperatureC)) / 3600.0
        return correction * (auxiliary + acceleration) + climateKw(temperatureC) / speed
    }

    // A stretch averaging walking pace is a jam; the auxiliary term divides by the speed.
    private fun clamp(speedKmh: Double) = speedKmh.coerceIn(MIN_SPEED_KMH, MAX_SPEED_KMH)

    /**
     * Battery energy for [km] at [speedKmh] while the road rises by [riseM]
     * (negative: falls). Height lost first stands in for the motor; only what
     * is left beyond that goes through recuperation.
     */
    private fun pieceKwh(km: Double, speedKmh: Double, riseM: Double, temperatureC: Double?): Double {
        val wheel = wheelKwhPerKm(speedKmh, temperatureC) * km + riseM * kwhPerMetreOfHeight
        val battery = if (wheel >= 0.0) wheel / efficiency(temperatureC) else wheel * recuperation(temperatureC)
        return battery + overheadKwhPerKm(speedKmh, temperatureC) * km
    }

    override fun energyKwh(route: Route, fromKm: Double, toKm: Double): Double {
        val from = fromKm.coerceIn(0.0, route.distanceKm)
        val to = toKm.coerceIn(from, route.distanceKm)
        if (to <= from) return 0.0

        var energy = 0.0
        forEachPiece(route, from, to) { km, kwhPerKm -> energy += km * kwhPerKm }
        return energy
    }

    override fun peakEnergyKwh(route: Route, fromKm: Double, toKm: Double): Double {
        val from = fromKm.coerceIn(0.0, route.distanceKm)
        val to = toKm.coerceIn(from, route.distanceKm)

        var energy = 0.0
        var peak = 0.0
        forEachPiece(route, from, to) { km, kwhPerKm ->
            energy += km * kwhPerKm
            peak = maxOf(peak, energy)
        }
        return peak
    }

    override fun reachKm(route: Route, fromKm: Double, availableKwh: Double): Double {
        val from = fromKm.coerceIn(0.0, route.distanceKm)
        var budget = availableKwh.coerceAtLeast(0.0)
        var reached = from
        var empty = budget <= 0.0

        forEachPiece(route, from, route.distanceKm) { km, kwhPerKm ->
            if (!empty) {
                val affordableKm = if (kwhPerKm <= 0.0) km else budget / kwhPerKm
                if (affordableKm >= km) {
                    reached += km
                    budget -= km * kwhPerKm
                } else {
                    reached += affordableKm
                    budget = 0.0
                    empty = true
                }
            }
        }

        // Past the end of the route there are no segments left to price, so what
        // is left of the budget is spent at the route's own average. Without
        // this the planner would think every route ends exactly at the range
        // limit and would plan a stop for a trip that comfortably makes it.
        if (!empty && budget > 0.0) {
            reached += budget / (kwhPer100KmAt(averageSpeedKmh(route), route.destinationTemperatureC) / 100.0)
        }
        return reached
    }

    /**
     * Walks the part of the route between [from] and [to], handing out the
     * length of each piece and its energy per km. A segment that both climbs
     * and drops is split into a climbing piece followed by a dropping one, in
     * proportion to the metres, so the summit is never underestimated. A route
     * without segments is one level piece at the route's average speed.
     */
    private inline fun forEachPiece(route: Route, from: Double, to: Double, action: (Double, Double) -> Unit) {
        if (to <= from) return
        if (route.segments.isEmpty()) {
            action(to - from, kwhPer100KmAt(averageSpeedKmh(route)) / 100.0)
            return
        }

        var covered = from
        for (segment in route.segments) {
            val segmentEnd = segment.fromKm + segment.distanceKm
            if (segmentEnd <= from || segment.distanceKm <= 0.0) continue
            if (segment.fromKm >= to) break

            val speed = segment.averageSpeedKmh
            val temperature = segment.temperatureC
            val height = segment.ascentM + segment.descentM
            val climbKm = if (height > 0.0) segment.distanceKm * segment.ascentM / height else segment.distanceKm
            val climbEnd = segment.fromKm + climbKm

            val climbOverlap = minOf(climbEnd, to) - maxOf(segment.fromKm, from)
            if (climbOverlap > 0.0) action(climbOverlap, pieceKwh(climbKm, speed, segment.ascentM, temperature) / climbKm)
            val dropOverlap = minOf(segmentEnd, to) - maxOf(climbEnd, from)
            if (dropOverlap > 0.0) {
                val dropKm = segment.distanceKm - climbKm
                action(dropOverlap, pieceKwh(dropKm, speed, -segment.descentM, temperature) / dropKm)
            }

            covered = minOf(segmentEnd, to)
            if (covered >= to) return
        }

        // Segments that stop short of the route's length — the contract rules it
        // out, but a gap must not silently cost nothing.
        if (covered < to) action(to - covered, kwhPer100KmAt(averageSpeedKmh(route), route.destinationTemperatureC) / 100.0)
    }

    private fun averageSpeedKmh(route: Route): Double =
        if (route.durationMinutes <= 0.0) FALLBACK_SPEED_KMH
        else route.distanceKm / route.durationMinutes * 60.0

    private companion object {
        const val MIN_SPEED_KMH = 10.0
        const val MAX_SPEED_KMH = 200.0
        const val FALLBACK_SPEED_KMH = 100.0
        const val GRAVITY = 9.81
        const val JOULES_PER_KWH = 3_600_000.0
    }
}

private const val WLTP_TEST_TEMPERATURE_C = 23.0
private const val COLDEST_C = -25.0
private const val HOTTEST_C = 45.0

private fun Double?.withinRange(): Double = (this ?: WLTP_TEST_TEMPERATURE_C).coerceIn(COLDEST_C, HOTTEST_C)

/** Air density against the WLTP test's, which the curve was measured at. */
private fun airDensityFactor(temperatureC: Double?): Double =
    (WLTP_TEST_TEMPERATURE_C + KELVIN) / (temperatureC.withinRange() + KELVIN)

/** A cold pack and drivetrain lose more on the way to the wheels and take back less when braking. */
private fun coldLossFactor(temperatureC: Double?): Double =
    1.0 + COLD_LOSS_PER_KELVIN * (COLD_LOSS_BELOW_C - temperatureC.withinRange()).coerceAtLeast(0.0)

/** Heating or air conditioning on top of the auxiliaries the curve already carries. */
private fun climateKw(temperatureC: Double?): Double {
    val outside = temperatureC.withinRange()
    return when {
        outside < HEATING_BELOW_C -> HEATING_KW_PER_KELVIN * (HEATING_BELOW_C - outside)
        outside > COOLING_ABOVE_C -> COOLING_KW_PER_KELVIN * (outside - COOLING_ABOVE_C)
        else -> 0.0
    }
}

private const val KELVIN = 273.15
private const val COLD_LOSS_BELOW_C = 10.0
private const val COLD_LOSS_PER_KELVIN = 0.004
private const val HEATING_BELOW_C = 15.0
private const val HEATING_KW_PER_KELVIN = 0.1
private const val COOLING_ABOVE_C = 25.0
private const val COOLING_KW_PER_KELVIN = 0.1

/** The backend's typical curve for a car without one, scaled until the WLTC reproduces [wltpKwhPer100Km]. */
internal fun genericRoadLoad(wltpKwhPer100Km: Double): RoadLoad {
    val curve = VehiclePhysics.generic(wltpKwhPer100Km, VehiclePhysics.TYPICAL_TEST_MASS_KG)
    return RoadLoad(
        f0 = curve.f0,
        f1 = curve.f1,
        f2 = curve.f2,
        massKg = VehiclePhysics.TYPICAL_TEST_MASS_KG,
        drivetrainEfficiency = VehiclePhysics.DRIVETRAIN_EFFICIENCY,
        auxiliaryPowerKw = VehiclePhysics.DRIVING_AUXILIARY_KW,
        recuperationShare = VehiclePhysics.RECUPERATION_SHARE,
        wltpKwhPer100Km = wltpKwhPer100Km,
    )
}

/**
 * Kinetic energy put in per metre driven, in J/kg, for a stretch averaging
 * [speedKmh]. Up to 92 km/h these are the WLTC phases; the drop towards
 * steady motorway driving above that is an assumption.
 */
internal fun kineticJoulesPerKgAndMetre(speedKmh: Double): Double {
    val points = KINETIC_BY_SPEED
    if (speedKmh <= points.first().first) return points.first().second
    for (i in 1 until points.size) {
        val (upperSpeed, upperValue) = points[i]
        if (speedKmh <= upperSpeed) {
            val (lowerSpeed, lowerValue) = points[i - 1]
            return lowerValue + (upperValue - lowerValue) * (speedKmh - lowerSpeed) / (upperSpeed - lowerSpeed)
        }
    }
    return points.last().second
}

private val KINETIC_BY_SPEED = listOf(
    18.9 to 0.207,
    39.5 to 0.199,
    56.7 to 0.134,
    92.0 to 0.125,
    120.0 to 0.06,
)
