package fr.notedefrais.web;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/** Corps des requêtes et réponses de la connexion par empreinte (clé d'appareil). */
public final class DeviceKeys {

    private DeviceKeys() {}

    /** Demande d'une clé pour l'appareil connecté, désigné par un libellé lisible. */
    public record Registration(@NotBlank @Size(max = 100) String label) {}

    /** Clé d'appareil présentée pour se connecter ou pour la révoquer. */
    public record Key(@NotBlank String deviceKey) {}
}
