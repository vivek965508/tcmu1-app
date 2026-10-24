# TCMU-1 Universal GSM Motor Controller & Smart Billing System (VS Code Project)

Yeh project aapke **TCMU-1 GSM Motor Controller** aur **Cash Memo Billing System** ke liye poora **Visual Studio Code (VS Code)** setup aur source code hai.

## Is Project Mein Kya-Kya Shamil Hai?

1. **`lib/main.dart`**: Complete Flutter Android App code jisme:
   - **Universal SMS Parser**: `*TCMU-1 USERS*` (`USER1 = 8081728811, USER2 = 7839455008, USER4 = 9236504217.`) ko automatically regex se read karke 4 user slots fill karta hai (aur `USER3` ko Empty dikhata hai).
   - **Future-Ready Timer (`3*X`)**: Universal config mein `3*X` ke start aur end reply ke liye alag input boxes hain. Abhi default mein yeh `PUMP STARTED` / `PUMP STOPPED` par kaam karega, aur jab aapke paas `3*X` ka exact message aaye, toh bas Settings mein paste karke Save kar dein!
   - **Case-Insensitive Physical Start/Stop**: Chahe machine `manual start`, `MANUAL START`, ya `Motor Manual Start` bheje, app bina case-sensitivity ke substring match karke turant timer chalu/band kar dega.
   - **Sticky Default Rate + Manual Amount Override**: Jo rate (₹/hr) aap ek baar daal denge, wahi agle har customer ke liye apne aap set rahega jab tak aap naya rate na daalein. Saath hi **Manual Amount Box** bhi hai jisme aap chahein toh seedha fixed rupaye (jaise ₹150) daal sakte hain.
   - **Simple Cash Memo (No Shop Name)**: Bill slip par koi fixed dukan ka naam nahi hai — seedha saaf **CASH MEMO** print/share hota hai.
   - **Phone Security (Fingerprint + Device PIN)**: `local_auth` package ke zariye jo aapke phone ka Fingerprint ya Lock Screen PIN hai, wahi is app aur Settings ko kholne ke kaam aayega.
2. **`android/app/src/main/AndroidManifest.xml`**: SMS (`SEND_SMS`, `RECEIVE_SMS`) aur Biometric (`USE_BIOMETRIC`, `USE_FINGERPRINT`) permissions pehle se configured hain.
3. **`pubspec.yaml`**: Saare zaroori packages (`telephony`, `local_auth`, `shared_preferences`, `share_plus`).

## VS Code Mein APK Kaise Banayein?

1. VS Code kholein aur **Flutter Extension** install karein.
2. Is folder ko VS Code mein `File -> Open Folder` se kholein.
3. Terminal (`Ctrl + ~`) kholkar yeh command chalayein:
   ```bash
   flutter pub get
   flutter build apk --release
   ```
4. Aapka taiyar APK `build/app/outputs/flutter-apk/app-release.apk` mein mil jayega!
