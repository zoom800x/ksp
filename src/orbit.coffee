# Utility functions and constants
TWO_PI = 2 * Math.PI
HALF_PI = 0.5 * Math.PI
GOLDEN_RATIO = (1 + Math.sqrt(5)) / 2

sinh = (angle) ->
  p = Math.exp(angle)
  (p - (1 / p)) * 0.5
  
cosh = (angle) ->
  p = Math.exp(angle)
  (p + (1 / p)) * 0.5

acosh = (n) ->
  Math.log(n + Math.sqrt(n * n - 1))

crossProduct = (a, b) ->
  r = new Array(3)
  r[0] = a[1] * b[2] - a[2] * b[1]
  r[1] = a[2] * b[0] - a[0] * b[2]
  r[2] = a[0] * b[1] - a[1] * b[0]
  r

normalize = (v) -> numeric.divVS(v, numeric.norm2(v))

projectToPlane = (p, n) -> numeric.subVV(p, numeric.mulSV(numeric.dot(p, n), n))

# Finds the minimum of f(x) between x1 and x2. Returns x.
# See: http://en.wikipedia.org/wiki/Golden_section_search
goldenSectionSearch = (x1, x2, f) ->
  k = 2 - GOLDEN_RATIO
  x3 = x2
  x2 = x1 + k * (x3 - x1)
  
  y2 = f(x2)
  
  loop
    if (x3 - x2) > (x2 - x1)
      x = x2 + k * (x3 - x2)
    else
      x = x2 - k * (x2 - x1)
    
    return (x3 + x1) / 2 if (x3 - x1) < (1e-2 * (x2 + x)) # Close enough
    
    y = f(x)
    if y < y2
      if (x3 - x2) > (x2 - x1) then x1 = x2 else x3 = x2
      x2 = x
      y2 = y
    else
      if (x3 - x2) > (x2 - x1) then x3 = x else x1 = x

# Finds the root of f(x) near x0 given df(x) = f'(x)
newtonsMethod = (x0, f, df) ->
  loop
    x = x0 - f(x0) / df(x0)
    return x if isNaN(x) or Math.abs(x - x0) < 1e-6 # Close enough
    x0 = x

(exports ? this).Orbit = class Orbit
  constructor: (@referenceBody, @semiMajorAxis, @eccentricity, inclination,
    longitudeOfAscendingNode, argumentOfPeriapsis, @meanAnomalyAtEpoch) ->
    @inclination = inclination * Math.PI / 180 if inclination?
    @longitudeOfAscendingNode = longitudeOfAscendingNode * Math.PI / 180 if longitudeOfAscendingNode?
    @argumentOfPeriapsis = argumentOfPeriapsis * Math.PI / 180 if argumentOfPeriapsis?
    if @isHyperbolic()
      @timeOfPeriapsisPassage = @meanAnomalyAtEpoch
      delete @meanAnomalyAtEpoch
  
  isHyperbolic: ->
    @eccentricity > 1
  
  apoapsis: ->
    @semiMajorAxis * (1 + @eccentricity)
  
  periapsis: ->
    @semiMajorAxis * (1 - @eccentricity)
  
  apoapsisAltitude: ->
    @apoapsis() - @referenceBody.radius
  
  periapsisAltitude: ->
    @periapsis() - @referenceBody.radius

  semiMinorAxis: ->
    e = @eccentricity
    @semiMajorAxis * Math.sqrt(1 - e * e)
  
  semiLatusRectum: ->
    e = @eccentricity
    @semiMajorAxis * (1 - e * e)
  
  meanMotion: ->
    a = Math.abs(@semiMajorAxis)
    Math.sqrt(@referenceBody.gravitationalParameter / (a * a * a))
  
  period: ->
    if @isHyperbolic() then Infinity else TWO_PI / @meanMotion()
    
  rotationToReferenceFrame: ->
    axisOfInclination = [Math.cos(-@argumentOfPeriapsis), Math.sin(-@argumentOfPeriapsis), 0]
    quaternion.concat(
      quaternion.fromAngleAxis(@longitudeOfAscendingNode + @argumentOfPeriapsis, [0, 0, 1]),
      quaternion.fromAngleAxis(@inclination, axisOfInclination))
  
  normalVector: ->
    quaternion.rotate(@rotationToReferenceFrame(), [0, 0, 1])
  
  phaseAngle: (orbit, t) ->
    n = @normalVector()
    p1 = @positionAtTrueAnomaly(@trueAnomalyAt(t))
    p2 = orbit.positionAtTrueAnomaly(orbit.trueAnomalyAt(t))
    p2 = numeric.subVV(p2, numeric.mulVS(n, numeric.dot(p2, n))) # Project p2 onto our orbital plane
    r1 = numeric.norm2(p1)
    r2 = numeric.norm2(p2)
    phaseAngle = Math.acos(numeric.dot(p1, p2) / (r1 * r2))
    phaseAngle = TWO_PI - phaseAngle if numeric.dot(crossProduct(p1, p2), n) < 0
    phaseAngle = phaseAngle - TWO_PI if orbit.semiMajorAxis < @semiMajorAxis
    phaseAngle
    
  # Orbital state at time t
  
  meanAnomalyAt: (t) ->
    if @isHyperbolic()
      (t - @timeOfPeriapsisPassage) * @meanMotion()
    else
      (@meanAnomalyAtEpoch + @meanMotion() * (t % @period())) % TWO_PI
  
  eccentricAnomalyAt: (t) ->
    e = @eccentricity
    M = @meanAnomalyAt(t)
    
    if @isHyperbolic()
      newtonsMethod M,
        (x) -> M - e * sinh(x) + x
        (x) -> 1 - e * cosh(x)
    else
      newtonsMethod M,
        (x) -> M + e * Math.sin(x) - x
        (x) -> e * Math.cos(x) - 1
  
  trueAnomalyAt: (t) ->
    e = @eccentricity
    if @isHyperbolic()
      H = @eccentricAnomalyAt(t)
      tA = Math.acos((e - cosh(H)) / (cosh(H) * e - 1))
      if H < 0 then -tA else tA
    else
      E = @eccentricAnomalyAt(t)
      tA = 2 * Math.atan2(Math.sqrt(1 + e) * Math.sin(E / 2), Math.sqrt(1 - e) * Math.cos(E / 2))
      if tA < 0 then tA + TWO_PI else tA
    
  # Orbital state at true anomaly
  
  eccentricAnomalyAtTrueAnomaly: (tA) ->
    e = @eccentricity
    if @isHyperbolic()
      cosTrueAnomaly = Math.cos(tA)
      H = acosh((e + cosTrueAnomaly) / (1 + e * cosTrueAnomaly))
      if tA < 0 then -H else H
    else
      E = 2 * Math.atan(Math.tan(tA/2) / Math.sqrt((1 + e) / (1 - e)))
      if E < 0 then E + TWO_PI else E
  
  meanAnomalyAtTrueAnomaly: (tA) ->
    e = @eccentricity
    if @isHyperbolic()
      H = @eccentricAnomalyAtTrueAnomaly(tA)
      e * sinh(H) - H
    else
      E = @eccentricAnomalyAtTrueAnomaly(tA)
      E - e * Math.sin(E)
  
  timeAtTrueAnomaly: (tA, t0 = 0) ->
    M = @meanAnomalyAtTrueAnomaly(tA)
    if @isHyperbolic()
      @timeOfPeriapsisPassage + M / @meanMotion() # Eq. 4.86
    else
      p = @period()
      t = (t0 - (t0 % p)) + (M - @meanAnomalyAtEpoch) / @meanMotion()
      if t < t0 then t + p else t
  
  radiusAtTrueAnomaly: (tA) ->
    e = @eccentricity
    @semiMajorAxis * (1 - e * e) / (1 + e * Math.cos(tA))
  
  altitudeAtTrueAnomaly: (tA) ->
    @radiusAtTrueAnomaly(tA) - @referenceBody.radius

  speedAtTrueAnomaly: (tA) ->
    Math.sqrt(@referenceBody.gravitationalParameter * (2 / @radiusAtTrueAnomaly(tA) - 1 / @semiMajorAxis))
  
  positionAtTrueAnomaly: (tA) ->
    r = @radiusAtTrueAnomaly(tA)
    quaternion.rotate(@rotationToReferenceFrame(), [r * Math.cos(tA), r * Math.sin(tA), 0])
    
  velocityAtTrueAnomaly: (tA) ->
    mu = @referenceBody.gravitationalParameter
    e = @eccentricity
    h = Math.sqrt( mu * @semiMajorAxis * (1 - e * e))
    r = @radiusAtTrueAnomaly(tA)
    
    sin = Math.sin(tA)
    cos = Math.cos(tA)
    
    vr = mu * e * sin / h
    vtA = h / r
    
    quaternion.rotate(@rotationToReferenceFrame(), [vr * cos - vtA * sin, vr * sin + vtA * cos, 0])
  
  trueAnomalyAtPosition: (p) ->
    p = quaternion.rotate(quaternion.conjugate(@rotationToReferenceFrame()), p)
    Math.atan2(p[1], p[0])


Orbit.fromJSON = (json) ->
  result = new Orbit(json.referenceBody, json.semiMajorAxis, json.eccentricity)
  result.inclination = json.inclination
  result.longitudeOfAscendingNode = json.longitudeOfAscendingNode
  result.argumentOfPeriapsis = json.argumentOfPeriapsis
  result.meanAnomalyAtEpoch = json.meanAnomalyAtEpoch
  result
  
Orbit.fromApoapsisAndPeriapsis = (referenceBody, apoapsis, periapsis, inclination, longitudeOfAscendingNode, argumentOfPeriapsis, meanAnomalyAtEpoch) ->
  [apoapsis, periapsis] = [periapsis, apoapsis] if apoapsis < periapsis
  semiMajorAxis = (apoapsis + periapsis) / 2
  eccentricity = apoapsis / semiMajorAxis - 1
  new Orbit(referenceBody, semiMajorAxis, eccentricity, inclination, longitudeOfAscendingNode, argumentOfPeriapsis, meanAnomalyAtEpoch)

Orbit.fromAltitudeAndSpeed = (referenceBody, altitude, speed, flightPathAngle, heading, latitude, longitude, t) ->
  # Convert to standard units
  radius = referenceBody.radius + altitude
  flightPathAngle = flightPathAngle * Math.PI / 180
  heading = heading * Math.PI / 180 if heading?
  latitude = latitude * Math.PI / 180 if latitude?
  longitude = longitude * Math.PI / 180 if longitude?
  
  mu = referenceBody.gravitationalParameter
  sinPhi= Math.sin(flightPathAngle)
  cosPhi= Math.cos(flightPathAngle)
  
  semiMajorAxis = 1 / (2 / radius - speed * speed / mu)
  eccentricity = Math.sqrt(Math.pow(radius * speed * speed / mu - 1, 2) * cosPhi * cosPhi + sinPhi * sinPhi)
  
  orbit = new Orbit(referenceBody, semiMajorAxis, eccentricity, 0, 0, 0, 0)
  
  e = eccentricity
  trueAnomaly = Math.acos((orbit.semiMajorAxis * (1 - e * e) / radius - 1) / e)
  trueAnomaly = TWO_PI - trueAnomaly if flightPathAngle < 0
  
  meanAnomaly = orbit.meanAnomalyAtTrueAnomaly(trueAnomaly)
  orbit.meanAnomalyAtEpoch = meanAnomaly - orbit.meanMotion() * (t % orbit.period())
  
  if heading? and latitude?
    orbit.inclination = Math.acos(Math.cos(latitude) * Math.sin(heading))
    orbitalAngleToAscendingNode = Math.atan2(Math.tan(latitude), Math.cos(heading))
    orbit.argumentOfPeriapsis = orbitalAngleToAscendingNode - trueAnomaly
    
    if longitude?
      equatorialAngleToAscendingNode = Math.atan2(Math.sin(latitude) * Math.sin(heading), Math.cos(heading))
      orbit.longitudeOfAscendingNode = referenceBody.siderealTimeAt(longitude - equatorialAngleToAscendingNode, t)
  
  orbit

Orbit.fromPositionAndVelocity = (referenceBody, position, velocity, t) ->
  # From: http://www.braeunig.us/space/interpl.htm#elements
  mu = referenceBody.gravitationalParameter
  r = numeric.norm2(position)
  v = numeric.norm2(velocity)
  
  specificAngularMomentum = crossProduct(position, velocity) # Eq. 5.21
  if specificAngularMomentum[0] != 0 or specificAngularMomentum[1] != 0
    nodeVector = normalize([-specificAngularMomentum[1], specificAngularMomentum[0], 0]) # Eq. 5.22
  else
    nodeVector = [1, 0, 0]
  eccentricityVector = numeric.mulSV(1 / mu, numeric.subVV(numeric.mulSV(v*v - mu / r, position), numeric.mulSV(numeric.dot(position, velocity), velocity))) # Eq. 5.23
  
  semiMajorAxis = 1 / (2 / r - v * v / mu) # Eq. 5.24
  eccentricity = numeric.norm2(eccentricityVector) # Eq. 5.25
  orbit = new Orbit(referenceBody, semiMajorAxis, eccentricity)
  
  orbit.inclination = Math.acos(specificAngularMomentum[2] / numeric.norm2(specificAngularMomentum)) # Eq. 5.26
  if eccentricity == 0
    orbit.argumentOfPeriapsis = 0
    orbit.longitudeOfAscendingNode = 0
  else
    orbit.longitudeOfAscendingNode = Math.acos(nodeVector[0]) # Eq. 5.27
    orbit.longitudeOfAscendingNode = TWO_PI - orbit.longitudeOfAscendingNode if nodeVector[1] < 0
    orbit.argumentOfPeriapsis = Math.acos(numeric.dot(nodeVector, eccentricityVector) / eccentricity) # Eq. 5.28
    orbit.argumentOfPeriapsis = TWO_PI - orbit.argumentOfPeriapsis if eccentricityVector[2] < 0
  
  trueAnomaly = Math.acos(numeric.dot(eccentricityVector, position) / (eccentricity * r)) # Eq. 5.29
  trueAnomaly = -trueAnomaly if numeric.dot(position, velocity) < 0
  
  meanAnomaly = orbit.meanAnomalyAtTrueAnomaly(trueAnomaly)
  if orbit.isHyperbolic()
    orbit.timeOfPeriapsisPassage = t - meanAnomaly / orbit.meanMotion()
  else
    orbit.meanAnomalyAtEpoch = meanAnomaly - orbit.meanMotion() * (t % orbit.period())
  
  orbit

Orbit.circularToHyperbolicDeltaV = circularToHyperbolicDeltaV = (v0, vinf, relativeInclination) ->
  v1 = Math.sqrt(vinf * vinf + 2 * v0 * v0) # Eq. 5.35
  if relativeInclination
    Math.sqrt(v0 * v0 + v1 * v1 - 2 * v0 * v1 * Math.cos(relativeInclination)) # Eq. 4.74
  else
    v1 - v0 # Eq. 5.36
  
ejectionAngle = (asymptote, eccentricity, prograde) ->
  e = eccentricity
  [ax, ay, az] = normalize(asymptote)
  
  # We have two equations of two unknowns (vx, vy):
  #   dot(v, asymptote) = cos(eta) = -1 / e  [Eq. 4.81]
  #   norm(v) = 1  [Unit vector]
  #   vz = 0  [Perpendicular to z-axis]
  #
  # Solution is defined iff:
  #   ay != 0 [because we are solving for vx first]
  
  # Intermediate terms
  g = ax / ay
  
  # Quadratic coefficients
  a = 1 + g * g
  b = 2 * g / (e * ay)
  c = 1 / (e * e * ay * ay) - 1
  
  # Quadratic formula without loss of significance (Numerical Recipes eq. 5.6.4)
  if b < 0
    q = -0.5 * (b - Math.sqrt(b * b - 4 * a * c))
  else
    q = -0.5 * (b + Math.sqrt(b * b - 4 * a * c))
    
  # Solution
  vx = q / a
  vy = -g * vx - 1 / (e * ay)
  
  if crossProduct([vx, vy, 0], [ax, ay, az])[2] < 0 # Wrong orbital direction
    vx = c / q
    vy = -g * vx - 1 / (e * ay)
  
  if crossProduct([vx, vy, 0], prograde)[2] < 0
    TWO_PI - Math.acos(numeric.dot([vx, vy, 0], prograde))
  else
    Math.acos(numeric.dot([vx, vy, 0], prograde))

Orbit.transfer = (transferType, referenceBody, t0, p0, v0, n0, t1, p1, v1, n1, initialOrbitalVelocity, finalOrbitalVelocity, originBody, planeChangeAngleToIntercept) ->
  dt = t1 - t0

  if transferType == "optimal"
    ballisticTransfer = Orbit.transfer("ballistic", referenceBody, t0, p0, v0, n0, t1, p1, v1, n1, initialOrbitalVelocity, finalOrbitalVelocity, originBody)
    return ballisticTransfer if ballisticTransfer.angle <= HALF_PI
    planeChangeTransfer = Orbit.transfer("optimalPlaneChange", referenceBody, t0, p0, v0, n0, t1, p1, v1, n1, initialOrbitalVelocity, finalOrbitalVelocity, originBody)
    return if ballisticTransfer.deltaV < planeChangeTransfer.deltaV then ballisticTransfer else planeChangeTransfer
  else if transferType == "optimalPlaneChange"
    if numeric.norm2(p0) > numeric.norm2(p1)
      # Transferring to a lower orbit, optimum time to change inclination is 90 degrees to intercept or sooner
      x1 = HALF_PI
      x2 = Math.PI
    else
      # Transferring to a higher orbit, the optimum time to change inclination is 90 degrees to intercept or later
      x1 = 0
      x2 = HALF_PI
    
    # This calculates an approximation of the optimal angle to intercept to perform the plane change.
    # The approximation does not take into account the change in the transfer orbit due to the change
    # in the target position rotated into the origin plane as the plane change axis changes.
    # This approximation should be valid so long as the transfer orbit's semi-major axis and eccentricity
    # does not change significantly with the change in the plane change axis.
    relativeInclination = Math.asin(numeric.dot(p1, n0) / numeric.norm2(p1))
    planeChangeRotation = quaternion.fromAngleAxis(-relativeInclination, crossProduct(p1, n0))
    p1InOriginPlane = quaternion.rotate(planeChangeRotation, p1)
    v1InOriginPlane = quaternion.rotate(planeChangeRotation, v1)
    ejectionVelocity = lambert(referenceBody.gravitationalParameter, p0, p1InOriginPlane, dt)[0]
    orbit = Orbit.fromPositionAndVelocity(referenceBody, p0, ejectionVelocity, t0)
    trueAnomalyAtIntercept = orbit.trueAnomalyAtPosition(p1InOriginPlane)
    x = goldenSectionSearch x1, x2, (x) ->
      planeChangeAngle = Math.atan2(Math.tan(relativeInclination), Math.sin(x))
      Math.abs(2 * orbit.speedAtTrueAnomaly(trueAnomalyAtIntercept - x) * Math.sin(0.5 * planeChangeAngle))

    # Refine the initial estimate by running the algorithm again
    planeChangeAngle = Math.atan2(Math.tan(relativeInclination), Math.sin(x))
    planeChangeAxis = quaternion.rotate(quaternion.fromAngleAxis(-x, n0), projectToPlane(p1, n0))
    planeChangeRotation = quaternion.fromAngleAxis(planeChangeAngle, planeChangeAxis)
    p1InOriginPlane = quaternion.rotate(planeChangeRotation, p1)
    v1InOriginPlane = quaternion.rotate(planeChangeRotation, v1)
    ejectionVelocity = lambert(referenceBody.gravitationalParameter, p0, p1InOriginPlane, dt)[0]
    orbit = Orbit.fromPositionAndVelocity(referenceBody, p0, ejectionVelocity, t0)
    trueAnomalyAtIntercept = orbit.trueAnomalyAtPosition(p1InOriginPlane)
    x = goldenSectionSearch x1, x2, (x) ->
      planeChangeAngle = Math.atan2(Math.tan(relativeInclination), Math.sin(x))
      Math.abs(2 * orbit.speedAtTrueAnomaly(trueAnomalyAtIntercept - x) * Math.sin(0.5 * planeChangeAngle))
    
    return Orbit.transfer("planeChange", referenceBody, t0, p0, v0, n0, t1, p1, v1, n1, initialOrbitalVelocity, finalOrbitalVelocity, originBody, x)
  else if transferType == "planeChange"
    planeChangeAngleToIntercept ?= HALF_PI
    relativeInclination = Math.asin(numeric.dot(p1, n0) / numeric.norm2(p1))
    planeChangeAngle = Math.atan2(Math.tan(relativeInclination), Math.sin(planeChangeAngleToIntercept))
    if planeChangeAngle != 0
      planeChangeAxis = quaternion.rotate(quaternion.fromAngleAxis(-planeChangeAngleToIntercept, n0), projectToPlane(p1, n0))
      planeChangeRotation = quaternion.fromAngleAxis(planeChangeAngle, planeChangeAxis)
      p1InOriginPlane = quaternion.rotate(quaternion.conjugate(planeChangeRotation), p1)
  
  transfer = {}
  
  # Assume a counter-clockwise transfer around the +z axis
  transferAngle = Math.acos(numeric.dot(p0, p1) / (numeric.norm2(p0) * numeric.norm2(p1)))
  transferAngle = TWO_PI - transferAngle if p0[0] * p1[1] - p0[1] * p1[0] < 0 # (p0 x p1).z

  if !planeChangeAngle or transferAngle <= HALF_PI
    [ejectionVelocity, insertionVelocity] = lambert(referenceBody.gravitationalParameter, p0, p1, dt)
    planeChangeDeltaV = 0
  else
    [ejectionVelocity, insertionVelocity] = lambert(referenceBody.gravitationalParameter, p0, p1InOriginPlane, dt)

    orbit = Orbit.fromPositionAndVelocity(referenceBody, p0, ejectionVelocity, t0)
    planeChangeTrueAnomaly = orbit.trueAnomalyAt(t1) - planeChangeAngleToIntercept
    planeChangeDeltaV = Math.abs(2 * orbit.speedAtTrueAnomaly(planeChangeTrueAnomaly) * Math.sin(planeChangeAngle / 2))
    planeChangeDeltaV = 0 if isNaN(planeChangeDeltaV)
    planeChangeTime = orbit.timeAtTrueAnomaly(planeChangeTrueAnomaly, t0)
    insertionVelocity = quaternion.rotate(planeChangeRotation, insertionVelocity)
  
  ejectionDeltaVector = numeric.subVV(ejectionVelocity, v0)
  ejectionDeltaV = numeric.norm2(ejectionDeltaVector) # This is actually the hyperbolic excess velocity if ejecting from a parking orbit
  ejectionInclination = Math.asin(numeric.dot(ejectionDeltaVector, n0) / ejectionDeltaV)
  if initialOrbitalVelocity
    ejectionDeltaV = circularToHyperbolicDeltaV(initialOrbitalVelocity, ejectionDeltaV, ejectionInclination)

  if finalOrbitalVelocity?
    insertionDeltaVector = numeric.subVV(insertionVelocity, v1)
    insertionDeltaV = numeric.norm2(insertionDeltaVector) # This is actually the hyperbolic excess velocity if inserting into a parking orbit
    insertionInclination = Math.asin(numeric.dot(insertionDeltaVector, n1) / insertionDeltaV)
    if finalOrbitalVelocity
      insertionDeltaV = circularToHyperbolicDeltaV(finalOrbitalVelocity, insertionDeltaV, 0)
  else
    insertionDeltaV = 0

  transfer.angle = transferAngle
  transfer.orbit = orbit
  transfer.ejectionVelocity = ejectionVelocity
  transfer.ejectionDeltaVector = ejectionDeltaVector
  transfer.ejectionInclination = ejectionInclination
  transfer.ejectionDeltaV = ejectionDeltaV
  transfer.planeChangeAngleToIntercept = planeChangeAngleToIntercept
  transfer.planeChangeDeltaV = planeChangeDeltaV
  transfer.planeChangeTime = planeChangeTime
  transfer.planeChangeAngle = if planeChangeTime? then planeChangeAngle else 0
  transfer.insertionVelocity = insertionVelocity
  transfer.insertionInclination = insertionInclination
  transfer.insertionDeltaV = insertionDeltaV
  transfer.deltaV = ejectionDeltaV + planeChangeDeltaV + insertionDeltaV

  if originBody # We calculate more details of the transfer if an originBody is provided
    transfer.orbit ?= Orbit.fromPositionAndVelocity(referenceBody, p0, transfer.ejectionVelocity, t0)
    
    if initialOrbitalVelocity
      # Ejection delta-v components
      vinf = numeric.norm2(ejectionDeltaVector)
      v1 = Math.sqrt(vinf * vinf + 2 * initialOrbitalVelocity * initialOrbitalVelocity) # Eq. 5.35
      transfer.ejectionNormalDeltaV = v1 * Math.sin(ejectionInclination)
      transfer.ejectionProgradeDeltaV = v1 * Math.cos(ejectionInclination) - initialOrbitalVelocity
      
      # Ejection angle to prograde
      mu = originBody.gravitationalParameter
      r = mu / (initialOrbitalVelocity * initialOrbitalVelocity)
      e = r * v1 * v1 / mu - 1 # Eq. 4.30 simplified for a flight path angle of 0
      transfer.ejectionAngle = ejectionAngle(ejectionDeltaVector, e, normalize(v0))
    else
      transfer.ejectionNormalDeltaV = ejectionDeltaV * Math.sin(ejectionInclination)
      transfer.ejectionProgradeDeltaV = ejectionDeltaV * Math.cos(ejectionInclination)
  
  transfer
