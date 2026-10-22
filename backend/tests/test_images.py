import hashlib
import io

import pytest
from PIL import Image

from app.errors import APIError
from app.services.images import prepare_image


def test_image_is_normalized_and_metadata_is_removed():
    output = io.BytesIO()
    image = Image.new("RGB", (80, 140), "white")
    exif = Image.Exif()
    exif[0x010E] = "private metadata"
    image.save(output, "JPEG", exif=exif)
    result = prepare_image(output.getvalue(), "image/jpeg", 6 * 1024 * 1024)
    assert result.sha256 == hashlib.sha256(result.data).hexdigest()
    with Image.open(io.BytesIO(result.data)) as normalized:
        assert normalized.format == "JPEG"
        assert len(normalized.getexif()) == 0
        assert normalized.size == (80, 140)


def test_empty_and_oversized_images_are_rejected_before_decoding():
    for data, maximum, status in [(b"", 100, 422), (b"too long", 2, 413)]:
        with pytest.raises(APIError) as error:
            prepare_image(data, "image/jpeg", maximum)
        assert error.value.status == status
