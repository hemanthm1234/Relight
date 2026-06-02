from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

INPUT_DIR = Path("example_relights")
OUTPUT_DIR = INPUT_DIR


def round_image(img, radius):
    mask = Image.new("L", img.size, 0)

    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, img.width, img.height),
        radius=radius,
        fill=255,
    )

    rounded = Image.new(
        "RGBA",
        img.size,
        (255, 255, 255, 0),
    )

    rounded.paste(img, (0, 0))
    rounded.putalpha(mask)

    return rounded


for i in [4]:

    left = Image.open(INPUT_DIR / f"{i}.jpg").convert("RGB")
    right = Image.open(INPUT_DIR / f"relit_{i}.png").convert("RGB")

    # ------------------------------------------------------------------
    # Match heights
    # ------------------------------------------------------------------
    if left.height != right.height:
        new_w = int(
            right.width * left.height / right.height
        )

        right = right.resize(
            (new_w, left.height),
            Image.LANCZOS,
        )

    H = left.height

    # ------------------------------------------------------------------
    # Dynamic sizing
    # ------------------------------------------------------------------
    FONT_SIZE = max(20, int(H * 0.05))

    INNER_RADIUS = max(12, int(H * 0.03))

    OUTER_RADIUS = max(18, int(H * 0.04))

    GAP = max(12, int(H * 0.025))

    PADDING = max(16, int(H * 0.035))

    TITLE_HEIGHT = max(40, int(H * 0.10))

    # ------------------------------------------------------------------
    # Font
    # ------------------------------------------------------------------
    try:
        font = ImageFont.truetype(
            "DejaVuSans-Bold.ttf",
            FONT_SIZE,
        )
    except:
        font = ImageFont.load_default()

    # ------------------------------------------------------------------
    # Rounded images
    # ------------------------------------------------------------------
    left = round_image(
        left,
        INNER_RADIUS,
    )

    right = round_image(
        right,
        INNER_RADIUS,
    )

    # ------------------------------------------------------------------
    # Canvas size
    # ------------------------------------------------------------------
    canvas_w = (
        left.width
        + right.width
        + GAP
        + 2 * PADDING
    )

    canvas_h = (
        max(left.height, right.height)
        + TITLE_HEIGHT
        + 2 * PADDING
    )

    card = Image.new(
        "RGBA",
        (canvas_w, canvas_h),
        (255, 255, 255, 255),
    )

    draw = ImageDraw.Draw(card)

    # ------------------------------------------------------------------
    # Positions
    # ------------------------------------------------------------------
    left_x = PADDING
    left_y = TITLE_HEIGHT + PADDING

    right_x = (
        left_x
        + left.width
        + GAP
    )

    right_y = left_y

    # ------------------------------------------------------------------
    # Paste images
    # ------------------------------------------------------------------
    card.paste(
        left,
        (left_x, left_y),
        left,
    )

    card.paste(
        right,
        (right_x, right_y),
        right,
    )

    # ------------------------------------------------------------------
    # Titles
    # ------------------------------------------------------------------
    left_title = "Original"
    right_title = "Relit"

    left_bbox = draw.textbbox(
        (0, 0),
        left_title,
        font=font,
    )

    right_bbox = draw.textbbox(
        (0, 0),
        right_title,
        font=font,
    )

    left_text_w = (
        left_bbox[2]
        - left_bbox[0]
    )

    right_text_w = (
        right_bbox[2]
        - right_bbox[0]
    )

    left_title_x = (
        left_x
        + (left.width - left_text_w) // 2
    )

    right_title_x = (
        right_x
        + (right.width - right_text_w) // 2
    )

    combined_bbox = draw.textbbox(
        (0, 0),
        left_title + right_title,
        font=font,
    )

    title_y = int(
        (TITLE_HEIGHT + PADDING - (combined_bbox[1] + combined_bbox[3])) / 2
    )

    draw.text(
        (left_title_x, title_y),
        left_title,
        fill="black",
        font=font,
    )

    draw.text(
        (right_title_x, title_y),
        right_title,
        fill="black",
        font=font,
    )

    # ------------------------------------------------------------------
    # Rounded outer card
    # ------------------------------------------------------------------
    outer_mask = Image.new(
        "L",
        (canvas_w, canvas_h),
        0,
    )

    ImageDraw.Draw(
        outer_mask
    ).rounded_rectangle(
        (0, 0, canvas_w, canvas_h),
        radius=OUTER_RADIUS,
        fill=255,
    )

    final_img = Image.new(
        "RGBA",
        (canvas_w, canvas_h),
        (255, 255, 255, 0),
    )

    final_img.paste(card, (0, 0))
    final_img.putalpha(outer_mask)

    output_path = (
        OUTPUT_DIR
        / f"showcase_{i}.png"
    )

    final_img.save(output_path)

    print(
        f"Saved: {output_path}"
    )