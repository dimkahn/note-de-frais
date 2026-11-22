package fr.notedefrais.expense;

/** Filtre de netteté appliqué après recadrage. L'original n'est jamais modifié. */
public enum ImageFilter {
    /** Aucun filtre, recadrage seul. */
    NONE,
    /** Égalisation locale du contraste (CLAHE) + masque flou (netteté). Par défaut. */
    ENHANCE,
    /** Accentuation forte des contours. */
    SHARPEN,
    /** Noir et blanc type « scanner » (seuillage adaptatif). */
    SCAN_BW
}
