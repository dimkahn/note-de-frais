package fr.notedefrais.imaging;

import fr.notedefrais.expense.ImageFilter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import nu.pattern.OpenCV;
import org.opencv.core.*;
import org.opencv.imgcodecs.Imgcodecs;
import org.opencv.imgproc.CLAHE;
import org.opencv.imgproc.Imgproc;

/**
 * Pipeline : décodage (orientation EXIF appliquée) → contour (imposé par l'utilisateur ou détecté)
 * → correction de perspective → filtre.
 *
 * <p>Les paramètres (seuils, CLAHE, masque flou, seuillage adaptatif) sont dupliqués dans
 * {@code app/lib/scan/document_scanner.dart} : les garder alignés.
 *
 * <p>La détection travaille sur une copie réduite (rapide, robuste au bruit) puis les coins sont
 * remis à l'échelle pour redresser l'image pleine résolution.
 */
public final class OpenCvImageProcessor implements ImageProcessor {

    static {
        OpenCV.loadLocally();
    }

    private static final double DETECTION_HEIGHT = 800;
    /** Un document doit couvrir au moins cette part de l'image pour être recadré. */
    private static final double MIN_AREA_RATIO = 0.10;
    private static final double MAX_AREA_RATIO = 0.98;
    private static final int JPEG_QUALITY = 90;
    /** Tolérances successives de l'approximation en quadrilatère (bords irréguliers, coins arrondis). */
    private static final double[] APPROX_TOLERANCES = {0.02, 0.03, 0.05};
    /** Passe « fond clair ». */
    private static final double WEAK_CLAHE_CLIP = 3.0;
    private static final double WEAK_CANNY_LOW = 20;
    private static final double WEAK_CANNY_HIGH = 60;
    /** Côté maximal en sortie : suffisant pour la lecture, raisonnable pour l'envoi à Claude. */
    private static final int MAX_OUTPUT_SIDE = 2400;

    @Override
    public ProcessedImage process(byte[] original, ImageFilter filter, Quad corners) {
        Mat src = Imgcodecs.imdecode(new MatOfByte(original), Imgcodecs.IMREAD_COLOR);
        if (src.empty()) {
            throw new ImageProcessingException("Image illisible ou format non supporté");
        }
        try (var scope = new MatScope(src)) {
            Optional<Point[]> quad = corners != null
                    ? Optional.of(toPoints(corners, src))
                    : detectDocument(src, scope);
            Mat doc = quad.map(c -> scope.add(warp(src, c))).orElse(src);
            Mat resized = scope.add(limitSize(doc));
            Mat filtered = scope.add(applyFilter(resized, filter, scope));
            return new ProcessedImage(encodeJpeg(filtered), quad.isPresent());
        }
    }

    private static Point[] toPoints(Quad quad, Mat src) {
        return Arrays.stream(quad.toPixels(src.cols(), src.rows()))
                .map(p -> new Point(p[0], p[1]))
                .toArray(Point[]::new);
    }

    // --- Détection ---

    /**
     * Deux passes : bords francs (fond sombre, seuils d'Otsu), puis, si rien n'est trouvé, bords
     * faibles (fond clair : contraste égalisé localement, seuils bas, contour refermé).
     */
    private Optional<Point[]> detectDocument(Mat src, MatScope scope) {
        double scale = Math.min(1.0, DETECTION_HEIGHT / src.rows());
        Mat small = scope.add(new Mat());
        Imgproc.resize(src, small, new Size(), scale, scale, Imgproc.INTER_AREA);

        Mat gray = scope.add(new Mat());
        Imgproc.cvtColor(small, gray, Imgproc.COLOR_BGR2GRAY);
        Imgproc.GaussianBlur(gray, gray, new Size(5, 5), 0);

        double imageArea = small.size().area();
        return findQuad(strongEdges(gray, scope), imageArea, scope)
                .or(() -> findQuad(weakEdges(gray, scope), imageArea, scope))
                .map(q -> scale(q, 1 / scale));
    }

    private static Mat strongEdges(Mat gray, MatScope scope) {
        Mat edges = scope.add(new Mat());
        double otsu = Imgproc.threshold(gray, scope.add(new Mat()), 0, 255, Imgproc.THRESH_BINARY | Imgproc.THRESH_OTSU);
        Imgproc.Canny(gray, edges, otsu * 0.5, otsu);
        Imgproc.dilate(edges, edges, scope.add(Imgproc.getStructuringElement(Imgproc.MORPH_RECT, new Size(3, 3))));
        return edges;
    }

    private static Mat weakEdges(Mat gray, MatScope scope) {
        Mat equalized = scope.add(new Mat());
        CLAHE clahe = Imgproc.createCLAHE(WEAK_CLAHE_CLIP, new Size(8, 8));
        clahe.apply(gray, equalized);
        Mat edges = scope.add(new Mat());
        Imgproc.Canny(equalized, edges, WEAK_CANNY_LOW, WEAK_CANNY_HIGH);
        Mat kernel = scope.add(Imgproc.getStructuringElement(Imgproc.MORPH_RECT, new Size(5, 5)));
        Imgproc.morphologyEx(edges, edges, Imgproc.MORPH_CLOSE, kernel);
        Imgproc.dilate(edges, edges, kernel);
        return edges;
    }

    /** Plus grand contour à 4 coins, convexe, d'une aire plausible ; approximation assouplie progressivement. */
    private static Optional<Point[]> findQuad(Mat edges, double imageArea, MatScope scope) {
        List<MatOfPoint> contours = new ArrayList<>();
        Imgproc.findContours(edges, contours, scope.add(new Mat()), Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE);
        contours.forEach(scope::add);
        return contours.stream()
                .sorted(Comparator.comparingDouble((MatOfPoint c) -> Imgproc.contourArea(c)).reversed())
                .limit(5)
                .map(c -> approximateQuad(c, imageArea, scope))
                .flatMap(Optional::stream)
                .findFirst();
    }

    private static Optional<Point[]> approximateQuad(MatOfPoint contour, double imageArea, MatScope scope) {
        MatOfPoint2f c2f = scope.add(new MatOfPoint2f(contour.toArray()));
        double perimeter = Imgproc.arcLength(c2f, true);
        for (double tolerance : APPROX_TOLERANCES) {
            MatOfPoint2f approx = scope.add(new MatOfPoint2f());
            Imgproc.approxPolyDP(c2f, approx, tolerance * perimeter, true);
            Point[] pts = approx.toArray();
            if (pts.length != 4 || !Imgproc.isContourConvex(new MatOfPoint(pts))) {
                continue;
            }
            double ratio = Imgproc.contourArea(new MatOfPoint(pts)) / imageArea;
            return ratio >= MIN_AREA_RATIO && ratio <= MAX_AREA_RATIO ? Optional.of(pts) : Optional.empty();
        }
        return Optional.empty();
    }

    private static Point[] scale(Point[] pts, double factor) {
        return Arrays.stream(pts).map(p -> new Point(p.x * factor, p.y * factor)).toArray(Point[]::new);
    }

    // --- Redressement ---

    private static Mat warp(Mat src, Point[] corners) {
        Point[] o = orderCorners(corners); // haut-gauche, haut-droit, bas-droit, bas-gauche
        double width = Math.max(distance(o[0], o[1]), distance(o[3], o[2]));
        double height = Math.max(distance(o[0], o[3]), distance(o[1], o[2]));
        var from = new MatOfPoint2f(o);
        var to = new MatOfPoint2f(new Point(0, 0), new Point(width - 1, 0),
                new Point(width - 1, height - 1), new Point(0, height - 1));
        Mat transform = Imgproc.getPerspectiveTransform(from, to);
        Mat out = new Mat();
        Imgproc.warpPerspective(src, out, transform, new Size(width, height), Imgproc.INTER_CUBIC);
        from.release();
        to.release();
        transform.release();
        return out;
    }

    static Point[] orderCorners(Point[] pts) {
        Point tl = Arrays.stream(pts).min(Comparator.comparingDouble(p -> p.x + p.y)).orElseThrow();
        Point br = Arrays.stream(pts).max(Comparator.comparingDouble(p -> p.x + p.y)).orElseThrow();
        Point tr = Arrays.stream(pts).min(Comparator.comparingDouble(p -> p.y - p.x)).orElseThrow();
        Point bl = Arrays.stream(pts).max(Comparator.comparingDouble(p -> p.y - p.x)).orElseThrow();
        return new Point[]{tl, tr, br, bl};
    }

    private static double distance(Point a, Point b) {
        return Math.hypot(a.x - b.x, a.y - b.y);
    }

    private static Mat limitSize(Mat src) {
        double factor = Math.min(1.0, MAX_OUTPUT_SIDE / (double) Math.max(src.cols(), src.rows()));
        Mat out = new Mat();
        if (factor < 1.0) {
            Imgproc.resize(src, out, new Size(), factor, factor, Imgproc.INTER_AREA);
        } else {
            src.copyTo(out);
        }
        return out;
    }

    // --- Filtres ---

    private static Mat applyFilter(Mat src, ImageFilter filter, MatScope scope) {
        return switch (filter) {
            case NONE -> src.clone();
            case ENHANCE -> unsharp(claheOnLightness(src, scope), 1.0, 1.5);
            case SHARPEN -> unsharp(src, 1.5, 2.0);
            case SCAN_BW -> scanBlackAndWhite(src, scope);
        };
    }

    /** Égalisation adaptative du contraste sur la luminance seulement (couleurs préservées). */
    private static Mat claheOnLightness(Mat src, MatScope scope) {
        Mat lab = scope.add(new Mat());
        Imgproc.cvtColor(src, lab, Imgproc.COLOR_BGR2Lab);
        List<Mat> channels = new ArrayList<>();
        Core.split(lab, channels);
        channels.forEach(c -> scope.add(c));
        CLAHE clahe = Imgproc.createCLAHE(2.0, new Size(8, 8));
        clahe.apply(channels.getFirst(), channels.getFirst());
        Core.merge(channels, lab);
        Mat out = scope.add(new Mat());
        Imgproc.cvtColor(lab, out, Imgproc.COLOR_Lab2BGR);
        return out;
    }

    /** Masque flou : out = src·(1+amount) − flou·amount. */
    private static Mat unsharp(Mat src, double sigma, double amount) {
        Mat blurred = new Mat();
        Imgproc.GaussianBlur(src, blurred, new Size(0, 0), sigma);
        Mat out = new Mat();
        Core.addWeighted(src, 1 + amount, blurred, -amount, 0, out);
        blurred.release();
        return out;
    }

    private static Mat scanBlackAndWhite(Mat src, MatScope scope) {
        Mat gray = scope.add(new Mat());
        Imgproc.cvtColor(src, gray, Imgproc.COLOR_BGR2GRAY);
        Mat out = new Mat();
        int block = Math.max(15, (Math.min(gray.cols(), gray.rows()) / 30) | 1);
        Imgproc.adaptiveThreshold(gray, out, 255, Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
                Imgproc.THRESH_BINARY, block, 12);
        return out;
    }

    private static byte[] encodeJpeg(Mat img) {
        var buffer = new MatOfByte();
        Imgcodecs.imencode(".jpg", img, buffer, new MatOfInt(Imgcodecs.IMWRITE_JPEG_QUALITY, JPEG_QUALITY));
        byte[] bytes = buffer.toArray();
        buffer.release();
        return bytes;
    }

    /** Libère toutes les matrices natives créées pendant un traitement. */
    private static final class MatScope implements AutoCloseable {
        private final List<Mat> mats = new ArrayList<>();

        MatScope(Mat first) {
            mats.add(first);
        }

        <T extends Mat> T add(T mat) {
            mats.add(mat);
            return mat;
        }

        @Override
        public void close() {
            mats.forEach(Mat::release);
        }
    }
}
