import hashlib
import io
import warnings
from dataclasses import dataclass

from PIL import Image, ImageOps, UnidentifiedImageError

from ..errors import APIError


@dataclass(frozen=True)
class PreparedImage:
    data: bytes
    sha256: str
    mime_type: str = "image/jpeg"


def prepare_image(data: bytes, content_type: str | None, maximum: int) -> PreparedImage:
    if not data:
        raise APIError(422, "empty_image", "Choose a non-empty receipt image.")
    if len(data) > maximum:
        raise APIError(413, "image_too_large", "The receipt image must be 6 MiB or smaller.")
    if content_type not in {"image/jpeg", "image/png"}:
        raise APIError(415, "unsupported_image", "Upload a JPEG or PNG image.")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as source:
                expected = "JPEG" if content_type == "image/jpeg" else "PNG"
                if source.format != expected:
                    raise APIError(
                        415,
                        "image_type_mismatch",
                        "The file content does not match its declared image type.",
                    )
                if source.width * source.height > 20_000_000 or getattr(source, "n_frames", 1) != 1:
                    raise APIError(
                        422,
                        "unsupported_image_dimensions",
                        "Use a single image no larger than 20 megapixels.",
                    )
                source.verify()
            with Image.open(io.BytesIO(data)) as source:
                upright = ImageOps.exif_transpose(source)
                if upright.mode in {"RGBA", "LA"} or "transparency" in upright.info:
                    rgba = upright.convert("RGBA")
                    image = Image.new("RGB", rgba.size, "white")
                    image.paste(rgba, mask=rgba.getchannel("A"))
                else:
                    image = upright.convert("RGB")
                image.thumbnail((4096, 4096), Image.Resampling.LANCZOS)
                output = io.BytesIO()
                # Re-encoding removes EXIF/GPS and other source metadata.
                image.save(output, format="JPEG", quality=90)
                result = output.getvalue()
                if len(result) > maximum:
                    raise APIError(413, "image_too_large", "Please use a smaller receipt image.")
    except APIError:
        raise
    except (
        UnidentifiedImageError,
        OSError,
        SyntaxError,
        ValueError,
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
    ) as error:
        raise APIError(
            422, "invalid_image", "This image could not be decoded. Choose a readable JPEG or PNG."
        ) from error
    return PreparedImage(result, hashlib.sha256(result).hexdigest())
