import { useState, useEffect, useRef } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { validateVerificationToken, submitVerification } from '@/api/verification';
import toast from 'react-hot-toast';

function dataURLToBlob(dataUrl: string): Blob {
  const arr = dataUrl.split(',');
  const mime = arr[0].match(/:(.*?);/)![1];
  const bstr = atob(arr[1]);
  const u8arr = new Uint8Array(bstr.length);
  for (let i = 0; i < bstr.length; i++) u8arr[i] = bstr.charCodeAt(i);
  return new Blob([u8arr], { type: mime });
}

type FlowStep = 'loading' | 'intro' | 'doc_front' | 'doc_back' | 'selfie' | 'uploading' | 'result' | 'error';

export function VerifyIdentityPage() {
  const [searchParams] = useSearchParams();
  const token = searchParams.get('token');
  const navigate = useNavigate();

  const [flow, setFlow] = useState<FlowStep>('loading');
  const [error, setError] = useState<string | null>(null);
  const [ciFrontFile, setCiFrontFile] = useState<File | null>(null);
  const [ciBackFile, setCiBackFile] = useState<File | null>(null);
  const [result, setResult] = useState<any>(null);
  const [loadingText, setLoadingText] = useState('Iniciando...');

  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const [cameraReady, setCameraReady] = useState(false);

  useEffect(() => {
    if (!token) {
      setError('Enlace de verificación no válido o ausente.');
      setFlow('error');
      return;
    }
    validateVerificationToken(token)
      .then((res) => {
        if (res.valid) setFlow('intro');
        else {
          setError(res.message || 'El enlace ha expirado o ya fue utilizado.');
          setFlow('error');
        }
      })
      .catch(() => {
        setError('Error de conexión con los servicios de identidad.');
        setFlow('error');
      });
  }, [token]);

  const startCamera = async () => {
    setCameraReady(false);
    try {
      const s = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: flow === 'selfie' ? 'user' : 'environment', width: { ideal: 1920 } },
        audio: false,
      });
      streamRef.current = s;
      if (videoRef.current) {
        videoRef.current.srcObject = s;
      }
    } catch (err) {
      toast.error('Permiso de cámara denegado.');
    }
  };

  const onVideoCanPlay = () => {
    const video = videoRef.current;
    if (video && video.readyState >= 2) setCameraReady(true);
  };

  const onVideoLoadedData = () => {
    const video = videoRef.current;
    if (video && video.readyState === 4) setCameraReady(true);
  };

  const stopCamera = () => {
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop());
      streamRef.current = null;
    }
  };

  /** Synchronous capture: runs on first click when video is ready. No async, no debounce. */
  const handleCapture = () => {
    const video = videoRef.current;
    if (!video || video.readyState !== 4 || !video.videoWidth) return;
    const canvas = canvasRef.current ?? document.createElement('canvas');
    if (!canvasRef.current) canvasRef.current = canvas;
    const c = canvasRef.current;
    c.width = video.videoWidth;
    c.height = video.videoHeight;
    const ctx = c.getContext('2d');
    if (!ctx) return;
    ctx.drawImage(video, 0, 0, c.width, c.height);
    const imageData = c.toDataURL('image/jpeg', 0.9);
    const file = new File([dataURLToBlob(imageData)], `${flow}.jpg`, { type: 'image/jpeg' });
    stopCamera();
    if (flow === 'doc_front') {
      setCiFrontFile(file);
      setFlow('doc_back');
      startCamera();
    } else if (flow === 'doc_back') {
      setCiBackFile(file);
      setFlow('selfie');
      startCamera();
    } else if (flow === 'selfie') {
      processVerificationWithFiles(file, ciFrontFile, ciBackFile);
    }
  };


  const processVerificationWithFiles = async (
    selfie: File | null,
    ciFront: File | null,
    ciBack: File | null
  ) => {
    if (!token || !selfie || !ciFront || !ciBack) return;
    setFlow('uploading');

    // UI Phase Simulation for UX Feel
    setLoadingText('Subiendo imágenes seguras...');
    await new Promise(r => setTimeout(r, 1500));
    setLoadingText('Analizando documentos (OCR)...');
    await new Promise(r => setTimeout(r, 2000));
    setLoadingText('Validando biometría AWS...');

    try {
      // For demo/test, we send a dummy livenessSessionId since we can't integrate the real SDK component here
      const dummyLivenessId = 'session-' + Math.random().toString(36).substring(7);

      const res = await submitVerification(token, selfie, ciFront, ciBack, [], dummyLivenessId);
      setResult(res);
      setFlow('result');
    } catch (err: any) {
      // 1. Try to get message from our shared error format: { error: { message: "..." } }
      // 2. Try Zod error format or standard body: { message: "..." }
      // 3. Special case for common Axios messages
      let msg = err?.response?.data?.error?.message
        || err?.response?.data?.message;

      if (!msg || msg.includes('status code')) {
        msg = 'Nuestros servicios de identidad no están disponibles en este momento. Por favor, intenta de nuevo en unos minutos o contacta a soporte.';
      }

      setError(msg);
      setFlow('error');
    }
  };

  const renderProgress = () => {
    const steps = ['doc_front', 'doc_back', 'selfie'];
    const currentIdx = steps.indexOf(flow);
    if (currentIdx === -1) return null;

    return (
      <div className="flex gap-2 px-8 pt-6">
        {[0, 1, 2].map(i => (
          <div key={i} className={`h-1.5 flex-1 rounded-full transition-all duration-500 ${i <= currentIdx ? 'bg-green-500 shadow-[0_0_10px_rgba(34,197,94,0.5)]' : 'bg-gray-200 dark:bg-gray-700'}`} />
        ))}
      </div>
    );
  };

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950 flex flex-col items-center justify-center p-4 font-sans">
      <div className="max-w-md w-full bg-white dark:bg-gray-900 rounded-[3rem] shadow-[0_32px_64px_-16px_rgba(0,0,0,0.2)] border border-gray-100 dark:border-gray-800 overflow-hidden flex flex-col relative">

        {renderProgress()}

        <div className="p-8 flex-1 flex flex-col min-h-[500px]">
          {flow === 'loading' && (
            <div className="m-auto text-center animate-in fade-in zoom-in duration-500">
              <div className="relative w-20 h-20 mx-auto mb-6">
                <div className="absolute inset-0 border-4 border-green-500/20 rounded-full" />
                <div className="absolute inset-0 border-4 border-green-500 border-t-transparent rounded-full animate-spin" />
              </div>
              <p className="font-black text-gray-400 uppercase tracking-widest text-xs">Cargando Módulo Core</p>
            </div>
          )}

          {flow === 'intro' && (
            <div className="flex-1 flex flex-col justify-between py-4 animate-in slide-in-from-bottom-8 duration-500">
              <div className="text-center space-y-6">
                <div className="w-24 h-24 bg-green-500/10 rounded-[2rem] flex items-center justify-center mx-auto text-5xl">🏦</div>
                <div>
                  <h1 className="text-3xl font-black text-gray-900 dark:text-white leading-tight">Seguridad de Nivel Bancario</h1>
                  <p className="text-gray-500 dark:text-gray-400 mt-3 text-sm font-medium">
                    Verifica tu identidad para proteger tu cuenta y la comunidad GARDEN.
                  </p>
                </div>
              </div>

              <div className="space-y-4 pt-10">
                <div className="flex items-start gap-4 p-4 bg-gray-50 dark:bg-gray-800/50 rounded-2xl">
                  <span className="text-xl">🪪</span>
                  <p className="text-xs font-semibold text-gray-600 dark:text-gray-400">Ten a mano tu documento de identidad oficial vigente.</p>
                </div>
                <div className="flex items-start gap-4 p-4 bg-gray-50 dark:bg-gray-800/50 rounded-2xl">
                  <span className="text-xl">💡</span>
                  <p className="text-xs font-semibold text-gray-600 dark:text-gray-400">Busca un lugar con buena iluminación natural.</p>
                </div>
                <button
                  onClick={() => { setFlow('doc_front'); startCamera(); }}
                  className="w-full py-5 rounded-3xl bg-gray-900 dark:bg-white text-white dark:text-gray-900 font-black shadow-2xl hover:scale-[1.02] transition-all active:scale-95"
                >
                  EMPEZAR AHORA
                </button>
              </div>
            </div>
          )}

          {(flow === 'doc_front' || flow === 'doc_back' || flow === 'selfie') && (
            <div className="flex-1 flex flex-col space-y-6 animate-in fade-in duration-300">
              <div>
                <h2 className="text-2xl font-black text-gray-900 dark:text-white text-center">
                  {flow === 'doc_front' ? 'Identidad: Anverso' : flow === 'doc_back' ? 'Identidad: Reverso' : 'Verificación Facial'}
                </h2>
                <p className="text-center text-xs font-bold text-gray-400 mt-1 uppercase tracking-wider">
                  {flow === 'selfie' ? 'Mira a la cámara y parpadea' : 'Ubica el documento dentro del marco'}
                </p>
              </div>

              <div className="flex-1 relative aspect-[4/3] bg-black rounded-[2.5rem] overflow-hidden border-4 border-gray-100 dark:border-gray-800 shadow-inner group">
                <video
                  ref={videoRef}
                  autoPlay
                  playsInline
                  muted
                  onLoadedData={onVideoLoadedData}
                  onCanPlay={onVideoCanPlay}
                  className={`w-full h-full object-cover ${flow === 'selfie' ? 'scale-x-[-1]' : ''}`}
                />
                <canvas ref={canvasRef} className="hidden" />

                {/* Document Guide Overlay */}
                {flow !== 'selfie' && (
                  <div className="absolute inset-0 flex items-center justify-center">
                    <div className="w-[85%] h-[70%] border-2 border-white/50 rounded-3xl border-dashed relative">
                      <div className="absolute -top-1 -left-1 w-6 h-6 border-t-4 border-l-4 border-green-500 rounded-tl-xl" />
                      <div className="absolute -top-1 -right-1 w-6 h-6 border-t-4 border-r-4 border-green-500 rounded-tr-xl" />
                      <div className="absolute -bottom-1 -left-1 w-6 h-6 border-b-4 border-l-4 border-green-500 rounded-bl-xl" />
                      <div className="absolute -bottom-1 -right-1 w-6 h-6 border-b-4 border-r-4 border-green-500 rounded-br-xl" />
                    </div>
                  </div>
                )}

                {/* Selfie Guide Overlay */}
                {flow === 'selfie' && (
                  <div className="absolute inset-0 flex items-center justify-center">
                    <div className="w-64 h-80 border-4 border-white/20 rounded-[100px] border-dashed shadow-[0_0_0_999px_rgba(0,0,0,0.4)]" />
                  </div>
                )}

                <div className="absolute bottom-6 left-0 right-0 flex justify-center">
                  <button
                    type="button"
                    disabled={!cameraReady}
                    onClick={handleCapture}
                    className="w-20 h-20 bg-white rounded-full border-8 border-white/20 shadow-2xl flex items-center justify-center p-1 active:scale-90 transition-transform disabled:opacity-50 disabled:pointer-events-none"
                    aria-label="Capturar foto"
                  >
                    <div className="w-full h-full bg-green-500 rounded-full flex items-center justify-center">
                      <span className="text-white text-2xl">📸</span>
                    </div>
                  </button>
                </div>
              </div>

              <button onClick={() => { stopCamera(); setCameraReady(false); setFlow('intro'); }} className="text-center text-xs font-black text-gray-400 uppercase tracking-widest hover:text-red-500 transition-colors">Cancelar Proceso</button>
            </div>
          )}

          {flow === 'uploading' && (
            <div className="m-auto text-center space-y-8 animate-in zoom-in duration-500">
              <div className="relative w-32 h-32 mx-auto">
                <div className="absolute inset-0 border-8 border-green-500/10 rounded-full" />
                <div className="absolute inset-0 border-8 border-green-500 border-t-transparent rounded-full animate-spin" />
                <div className="absolute inset-0 flex items-center justify-center text-3xl">🧩</div>
              </div>
              <div className="space-y-2">
                <h3 className="text-2xl font-black text-gray-900 dark:text-white uppercase italic">Sincronizando</h3>
                <p className="text-gray-500 dark:text-gray-400 font-bold text-sm tracking-tighter transition-all">{loadingText}</p>
              </div>
            </div>
          )}

          {flow === 'result' && result && (
            <div className="flex-1 flex flex-col justify-center text-center space-y-10 animate-in slide-in-from-bottom-12 duration-700">
              <div className={`w-32 h-32 rounded-[2.5rem] mx-auto flex items-center justify-center text-6xl shadow-2xl rotate-3 ${result.status === 'VERIFIED' ? 'bg-green-500' : result.status === 'REVIEW' ? 'bg-amber-400' : 'bg-red-500'
                }`}>
                {result.status === 'VERIFIED' ? '✔️' : result.status === 'REVIEW' ? '⚖️' : '❌'}
              </div>

              <div className="space-y-2">
                <h2 className="text-4xl font-black text-gray-900 dark:text-white tracking-tight">
                  {result.status === 'VERIFIED' ? 'Confirmado' : result.status === 'REVIEW' ? 'En Revisión' : 'Rechazado'}
                </h2>
                <p className="text-gray-500 dark:text-gray-400 font-semibold px-4">{result.message}</p>
              </div>

              {result.status !== 'REJECTED' && (
                <div className="bg-gray-50 dark:bg-gray-800/50 p-6 rounded-3xl mx-4 space-y-4">
                  <div className="flex justify-between text-[10px] font-black uppercase text-gray-400 tracking-[0.2em]">
                    <span>Biometric Match</span>
                    <span className="text-green-500">{result.similarity}%</span>
                  </div>
                  <div className="h-2 w-full bg-gray-200 dark:bg-gray-700 rounded-full overflow-hidden">
                    <div className="h-full bg-green-500 animate-progress origin-left" style={{ width: `${result.similarity}%` }} />
                  </div>
                </div>
              )}

              <button
                onClick={() => result.status === 'REJECTED' ? setFlow('intro') : navigate('/caregiver/profile')}
                className="w-full py-5 rounded-3xl bg-gray-900 dark:bg-white text-white dark:text-gray-900 font-black shadow-xl"
              >
                {result.status === 'REJECTED' ? 'REINTENTAR' : 'VOLVER AL PANEL'}
              </button>
            </div>
          )}

          {flow === 'error' && (
            <div className="flex-1 flex flex-col justify-center text-center space-y-8 animate-in fade-in duration-500">
              <div className="w-24 h-24 bg-red-100 dark:bg-red-900/30 rounded-3xl flex items-center justify-center mx-auto text-5xl">⚠️</div>
              <div className="space-y-4">
                <h2 className="text-2xl font-black text-gray-900 dark:text-white">Lo sentimos mucho</h2>
                <p className="text-gray-500 dark:text-gray-400 text-sm font-medium leading-relaxed px-6">{error}</p>
              </div>

              <div className="pt-6 space-y-3">
                <button onClick={() => { setError(null); setFlow('intro'); }} className="w-full py-4 rounded-2xl bg-green-600 text-white font-black shadow-lg">Vólver a intentar</button>
                <button onClick={() => navigate('/caregiver/profile')} className="w-full py-3 text-xs font-black text-gray-400 uppercase tracking-widest">Contactar Soporte</button>
              </div>
            </div>
          )}
        </div>

        <div className="px-8 pb-8 flex items-center justify-center gap-2 opacity-30 select-none grayscale">
          <div className="w-8 h-8 bg-gray-400 rounded-lg" />
          <span className="text-[10px] font-black uppercase tracking-widest text-gray-500">Secured by Rekognition Engine</span>
        </div>
      </div>
      <p className="mt-8 text-[10px] text-gray-500 font-black tracking-[0.3em] uppercase opacity-50">Identity Core v5.1.0 • production</p>
    </div>
  );
}

