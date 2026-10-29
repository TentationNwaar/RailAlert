// Textes des notifications dans les 4 langues de l'app (mêmes traductions que Translations.swift).

const TEXTS = {
  trainCancelled: { fr: 'Train supprimé : %s', de: 'Zug fällt aus: %s', it: 'Treno soppresso: %s', en: 'Train cancelled: %s' },
  trainCancelledBody: { fr: 'Le train de %s%s est supprimé.', de: 'Der Zug um %s%s fällt aus.', it: 'Il treno delle %s%s è soppresso.', en: 'The %s%s train is cancelled.' },
  delay: { fr: 'Retard de %d min : %s', de: '%d Min. Verspätung: %s', it: 'Ritardo di %d min: %s', en: '%d min delay: %s' },
  delayBody: { fr: 'Le train de %s%s partira vers %s.', de: 'Der Zug um %s%s fährt ca. um %s ab.', it: 'Il treno delle %s%s partirà verso le %s.', en: 'The %s%s train will leave around %s.' },
  alternative: { fr: 'Alternative : %s', de: 'Alternative: %s', it: 'Alternativa: %s', en: 'Alternative: %s' },
  arrival: { fr: 'arrivée %s', de: 'Ankunft %s', it: 'arrivo %s', en: 'arrives %s' },
  track: { fr: 'voie %s', de: 'Gleis %s', it: 'binario %s', en: 'platform %s' },
  trackChange: { fr: 'Changement de voie : %s', de: 'Gleisänderung: %s', it: 'Cambio di binario: %s', en: 'Platform change: %s' },
  trackChangeBodyFrom: { fr: 'Le train de %s part de la voie %s (au lieu de %s).', de: 'Der Zug um %s fährt ab Gleis %s (statt %s).', it: 'Il treno delle %s parte dal binario %s (invece del %s).', en: 'The %s train leaves from platform %s (instead of %s).' },
  trackChangeBody: { fr: 'Le train de %s part de la voie %s.', de: 'Der Zug um %s fährt ab Gleis %s.', it: 'Il treno delle %s parte dal binario %s.', en: 'The %s train leaves from platform %s.' },
  onTrip: { fr: '%s sur ton trajet %s', de: '%s auf deiner Strecke %s', it: '%s sul tuo tragitto %s', en: '%s on your trip %s' },
  ongoing: { fr: ' (en cours)', de: ' (laufend)', it: ' (in corso)', en: ' (ongoing)' },
  worksInterruption: { fr: 'Travaux · interruption', de: 'Bauarbeiten · Unterbruch', it: 'Lavori · interruzione', en: 'Works · interruption' },
  works: { fr: 'Travaux', de: 'Bauarbeiten', it: 'Lavori', en: 'Construction work' },
  interruption: { fr: 'Interruption', de: 'Unterbruch', it: 'Interruzione', en: 'Interruption' },
  replacementBus: { fr: 'Bus de remplacement entre %s et %s.', de: 'Bahnersatzbus zwischen %s und %s.', it: 'Bus sostitutivo tra %s e %s.', en: 'Rail replacement bus between %s and %s.' },
  replacementBusBody: { fr: 'Le train est remplacé par un bus sur ce tronçon. Prévois plus de temps.', de: 'Der Zug wird auf diesem Abschnitt durch einen Bus ersetzt. Plane mehr Zeit ein.', it: 'Il treno è sostituito da un bus su questa tratta. Prevedi più tempo.', en: 'The train is replaced by a bus on this section. Allow extra time.' },
  deviation: { fr: 'Itinéraire modifié : ce train ne suit pas son parcours habituel.', de: 'Geänderte Route: Dieser Zug fährt nicht auf seiner üblichen Strecke.', it: 'Percorso modificato: questo treno non segue il suo percorso abituale.', en: 'Route changed: this train is not following its usual route.' },
  extraTrain: { fr: 'Train supplémentaire, absent de l\'horaire habituel.', de: 'Extrazug, nicht im regulären Fahrplan.', it: 'Treno supplementare, non presente nell\'orario abituale.', en: 'Extra train, not in the regular timetable.' },
  trafficInfo: { fr: 'Info trafic : %s', de: 'Verkehrsinfo: %s', it: 'Info traffico: %s', en: 'Travel update: %s' },
  trainMessage: { fr: 'Train de %s : %s', de: 'Zug um %s: %s', it: 'Treno delle %s: %s', en: '%s train: %s' },
  early: { fr: 'Départ en avance : %s', de: 'Frühere Abfahrt: %s', it: 'Partenza anticipata: %s', en: 'Early departure: %s' },
  earlyBody: { fr: 'Le départ de %s%s est annoncé %d min plus tôt, à %s.', de: 'Die Abfahrt um %s%s ist %d Min. früher angekündigt, um %s.', it: 'La partenza delle %s%s è annunciata con %d min di anticipo, alle %s.', en: 'The %s%s departure is announced %d min early, at %s.' },
  transferTight: { fr: 'Correspondance serrée : %s', de: 'Knapper Anschluss: %s', it: 'Coincidenza stretta: %s', en: 'Tight connection: %s' },
  transferMissed: { fr: 'Correspondance compromise : %s', de: 'Anschluss gefährdet: %s', it: 'Coincidenza a rischio: %s', en: 'Connection at risk: %s' },
  transferTightBody: { fr: 'Il ne restera que %d min pour changer à %s.', de: 'Es bleiben nur noch %d Min. zum Umsteigen in %s.', it: 'Resteranno solo %d min per cambiare a %s.', en: 'Only %d min will be left to change at %s.' },
  transferMissedBody: { fr: 'Avec le retard, la correspondance à %s sera probablement manquée, sauf si elle attend.', de: 'Wegen der Verspätung wird der Anschluss in %s wohl verpasst, ausser er wartet.', it: 'Con il ritardo, la coincidenza a %s sarà probabilmente persa, salvo che aspetti.', en: 'With the delay, the connection at %s will probably be missed unless it waits.' },
  disruption: { fr: 'Perturbation', de: 'Störung', it: 'Perturbazione', en: 'Disruption' },
};

/** Texte traduit ; les %s et %d sont remplacés dans l'ordre. */
export function t(language, key, ...args) {
  const entry = TEXTS[key];
  let text = entry?.[language] ?? entry?.fr ?? key;
  for (const arg of args) text = text.replace(/%[sd]/, String(arg));
  return text;
}

export function alertLabel(language, alert) {
  if (alert.isConstruction) return t(language, alert.isInterruption ? 'worksInterruption' : 'works');
  return t(language, alert.isInterruption ? 'interruption' : 'disruption');
}
