#!/bin/bash
# deploy-web.sh — Build Flutter web y despliega a Vercel (producción)
# Uso: ./deploy-web.sh
set -e

cd garden-app

echo "▶ flutter clean..."
flutter clean

echo "▶ flutter build web..."
flutter build web \
  --dart-define=API_URL=https://garden-api-1ldd.onrender.com/api \
  --dart-define=SENTRY_DSN="" \
  --dart-define=POSTHOG_API_KEY=""

echo "▶ Parcheando bootstrap Firebase..."
sed -i '' 's|https://www.gstatic.com/firebasejs/|https://cdn.jsdelivr.net/npm/firebase@10.14.1/|g' build/web/index.html

echo "▶ Copiando a .vercel/output/static/..."
rm -rf ../.vercel/output/static/*
cp -r build/web/. ../.vercel/output/static/

# Config SPA: todas las rutas deben servir index.html (Flutter web = SPA)
# Sin esto, rutas directas como /mobile-verify retornan 404 en Vercel.
echo "▶ Escribiendo .vercel/output/config.json (SPA routing)..."
cat > ../.vercel/output/config.json << 'EOF'
{
  "version": 3,
  "routes": [
    { "handle": "filesystem" },
    { "src": "/(.*)", "dest": "/index.html" }
  ]
}
EOF

LOCAL_MD5=$(md5 build/web/main.dart.js | awk '{print $4}')
echo "▶ LOCAL MD5: $LOCAL_MD5"

cd ..
echo "▶ Desplegando a Vercel producción..."
vercel deploy --prebuilt --prod --scope saimateovb-8767s-projects

echo ""
echo "▶ Verificando MD5 en producción..."
PROD_MD5=$(curl -s "https://garden-mvp-three.vercel.app/main.dart.js" -o /tmp/deploy_check.js && md5 /tmp/deploy_check.js | awk '{print $4}')
echo "LOCAL: $LOCAL_MD5"
echo "PROD:  $PROD_MD5"

if [ "$LOCAL_MD5" = "$PROD_MD5" ]; then
  echo "✅ Deploy verificado — MD5 coincide"
else
  echo "❌ ADVERTENCIA: MD5 no coincide — puede que no sea la versión correcta"
fi
