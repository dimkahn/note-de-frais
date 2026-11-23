package fr.notedefrais.account;

/** Clé d'appareil inconnue ou révoquée : l'appareil doit se reconnecter avec son mot de passe. */
public class InvalidDeviceKeyException extends RuntimeException {
    public InvalidDeviceKeyException() {
        super("Connexion par empreinte expirée ou désactivée");
    }
}
