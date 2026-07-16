// Apparent solar time is projected on the UTC calendar deliberately. Civil
// timezone and daylight-saving rules must never enter this formatter.
function projectedText(utcMilliseconds, utcOffsetSeconds) {
  const apparentSolarDate = new Date(utcMilliseconds + utcOffsetSeconds * 1000);
  const padded = value => String(value).padStart(2, "0");
  return padded(apparentSolarDate.getUTCHours())
    + ":" + padded(apparentSolarDate.getUTCMinutes())
    + ":" + padded(apparentSolarDate.getUTCSeconds());
}
