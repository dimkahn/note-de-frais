package fr.notedefrais.imaging;

/** Résultat du traitement : JPEG prêt à l'affichage/extraction et indicateur de recadrage. */
public record ProcessedImage(byte[] jpeg, boolean cropped) {}
