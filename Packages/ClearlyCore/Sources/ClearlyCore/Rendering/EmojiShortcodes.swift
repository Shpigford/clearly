import Foundation

public enum EmojiShortcodes {
    public static let lookup: [String: String] = [
        // Smileys
        "smile": "😄", "laughing": "😆", "blush": "😊", "smiley": "😃",
        "grinning": "😀", "wink": "😉", "heart_eyes": "😍", "kissing_heart": "😘",
        "stuck_out_tongue_winking_eye": "😜", "sunglasses": "😎", "smirk": "😏",
        "thinking": "🤔", "joy": "😂", "rofl": "🤣", "relieved": "😌",
        "unamused": "😒", "sweat_smile": "😅", "sob": "😭", "cry": "😢",
        "scream": "😱", "angry": "😠", "rage": "😡", "sleeping": "😴",
        "mask": "😷", "skull": "💀", "alien": "👽", "robot": "🤖",
        "clown_face": "🤡", "nerd_face": "🤓", "shushing_face": "🤫",
        "zany_face": "🤪", "pleading_face": "🥺", "yawning_face": "🥱",

        // Gestures
        "thumbsup": "👍", "+1": "👍", "thumbsdown": "👎", "-1": "👎",
        "wave": "👋", "clap": "👏", "ok_hand": "👌", "raised_hands": "🙌",
        "pray": "🙏", "muscle": "💪", "point_up": "☝️", "point_down": "👇",
        "point_left": "👈", "point_right": "👉", "crossed_fingers": "🤞",
        "v": "✌️", "vulcan_salute": "🖖", "writing_hand": "✍️",

        // People
        "man": "👨", "woman": "👩", "boy": "👦", "girl": "👧",
        "baby": "👶", "person_frowning": "🙍", "person_shrugging": "🤷",

        // Hearts & Emotions
        "heart": "❤️", "broken_heart": "💔", "sparkling_heart": "💖",
        "blue_heart": "💙", "green_heart": "💚", "yellow_heart": "💛",
        "purple_heart": "💜", "black_heart": "🖤", "white_heart": "🤍",
        "orange_heart": "🧡", "fire": "🔥", "star": "⭐", "star2": "🌟",
        "sparkles": "✨", "boom": "💥", "zap": "⚡", "100": "💯",

        // Nature
        "sunny": "☀️", "cloud": "☁️", "umbrella": "☂️", "snowflake": "❄️",
        "rainbow": "🌈", "earth_americas": "🌎", "earth_africa": "🌍",
        "earth_asia": "🌏", "crescent_moon": "🌙",
        "sun_with_face": "🌞", "full_moon_with_face": "🌝",

        // Animals
        "dog": "🐶", "cat": "🐱", "mouse": "🐭", "bear": "🐻",
        "panda_face": "🐼", "monkey_face": "🐵", "chicken": "🐔",
        "penguin": "🐧", "frog": "🐸", "snail": "🐌", "bug": "🐛",
        "bee": "🐝", "butterfly": "🦋", "unicorn": "🦄", "fox_face": "🦊",
        "owl": "🦉", "wolf": "🐺", "octopus": "🐙", "whale": "🐳",
        "dolphin": "🐬", "turtle": "🐢", "snake": "🐍", "bird": "🐦",

        // Food
        "apple": "🍎", "green_apple": "🍏", "pizza": "🍕", "hamburger": "🍔",
        "fries": "🍟", "coffee": "☕", "beer": "🍺", "wine_glass": "🍷",
        "cake": "🍰", "cookie": "🍪", "doughnut": "🍩", "ice_cream": "🍦",
        "taco": "🌮", "burrito": "🌯", "popcorn": "🍿", "champagne": "🍾",
        "tropical_drink": "🍹", "tea": "🍵",

        // Activities & Objects
        "soccer": "⚽", "basketball": "🏀", "football": "🏈",
        "baseball": "⚾", "tennis": "🎾", "trophy": "🏆", "medal_sports": "🏅",
        "guitar": "🎸", "microphone": "🎤", "headphones": "🎧",
        "art": "🎨", "video_game": "🎮", "dart": "🎯", "dice": "🎲",
        "bowling": "🎳", "tada": "🎉", "confetti_ball": "🎊", "balloon": "🎈",
        "gift": "🎁", "ribbon": "🎀",

        // Travel & Transport
        "rocket": "🚀", "airplane": "✈️", "car": "🚗", "bus": "🚌",
        "bike": "🚲", "ship": "🚢", "helicopter": "🚁",

        // Tech & Office
        "computer": "💻", "keyboard": "⌨️", "phone": "📱",
        "email": "📧", "envelope": "✉️", "pencil": "✏️", "pencil2": "✏️",
        "pen": "🖊️", "memo": "📝", "book": "📖", "books": "📚",
        "bookmark": "🔖", "link": "🔗", "paperclip": "📎",
        "scissors": "✂️", "lock": "🔒", "unlock": "🔓",
        "key": "🔑", "bulb": "💡", "gear": "⚙️", "wrench": "🔧",
        "hammer": "🔨", "nut_and_bolt": "🔩", "mag": "🔍", "mag_right": "🔎",
        "microscope": "🔬", "telescope": "🔭", "satellite": "📡",
        "battery": "🔋", "electric_plug": "🔌", "floppy_disk": "💾",
        "cd": "💿", "dvd": "📀", "camera": "📷", "tv": "📺",
        "desktop_computer": "🖥️", "printer": "🖨️", "bell": "🔔",
        "loudspeaker": "📢", "mega": "📣", "hourglass": "⌛",
        "alarm_clock": "⏰", "stopwatch": "⏱️", "timer_clock": "⏲️",
        "calendar": "📅", "date": "📅",

        // Symbols
        "white_check_mark": "✅", "x": "❌", "heavy_check_mark": "✔️",
        "heavy_multiplication_x": "✖️", "exclamation": "❗", "question": "❓",
        "warning": "⚠️", "no_entry": "⛔", "recycle": "♻️",
        "heavy_plus_sign": "➕", "heavy_minus_sign": "➖",
        "bangbang": "‼️", "interrobang": "⁉️",
        "arrow_up": "⬆️", "arrow_down": "⬇️", "arrow_left": "⬅️",
        "arrow_right": "➡️", "arrow_upper_right": "↗️",
        "arrows_counterclockwise": "🔄", "back": "🔙",
        "checkered_flag": "🏁", "triangular_flag_on_post": "🚩",
        "white_flag": "🏳️", "black_flag": "🏴",
        "copyright": "©️", "registered": "®️", "tm": "™️",
        "hash": "#️⃣", "zero": "0️⃣", "one": "1️⃣", "two": "2️⃣",
        "three": "3️⃣", "four": "4️⃣", "five": "5️⃣",
        "six": "6️⃣", "seven": "7️⃣", "eight": "8️⃣", "nine": "9️⃣",
        "ten": "🔟", "abc": "🔤", "abcd": "🔡",
        "red_circle": "🔴", "orange_circle": "🟠", "yellow_circle": "🟡",
        "green_circle": "🟢", "blue_circle": "🔵", "purple_circle": "🟣",
        "white_circle": "⚪", "black_circle": "⚫",
        "red_square": "🟥", "blue_square": "🟦", "green_square": "🟩",

        // Flags
        "flag_us": "🇺🇸", "flag_gb": "🇬🇧", "flag_fr": "🇫🇷",
        "flag_de": "🇩🇪", "flag_jp": "🇯🇵", "flag_cn": "🇨🇳",
        "flag_kr": "🇰🇷", "flag_br": "🇧🇷", "flag_in": "🇮🇳",
        "flag_au": "🇦🇺", "flag_ca": "🇨🇦", "flag_es": "🇪🇸",
        "flag_it": "🇮🇹", "flag_mx": "🇲🇽",
    ]
}
