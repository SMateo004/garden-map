import { Server as SocketServer } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import { Server as HttpServer } from 'http';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { getRedisClient } from '../config/redis.js';
import prisma from '../config/database.js';
import logger from '../shared/logger.js';

let io: SocketServer | null = null;

export function initSocketServer(httpServer: HttpServer): SocketServer {
    const explicitOrigins = env.ALLOWED_ORIGINS
        .split(',')
        .map((o: string) => o.trim())
        .filter(Boolean);

    const devPatterns: (RegExp | string)[] = env.NODE_ENV !== 'production'
        ? [
            /^http:\/\/localhost:\d+$/,
            /^http:\/\/127\.0\.0\.1:\d+$/,
            /^http:\/\/192\.168\.\d+\.\d+:\d+$/,
          ]
        : [];

    // Redis adapter: pub + sub son clientes separados (requisito de ioredis)
    const redisPub = getRedisClient();
    const redisSub = redisPub?.duplicate() ?? null;
    // El duplicate no hereda el error handler — añadirlo para evitar crash
    redisSub?.on('error', (err: Error) => logger.error('Redis sub error', { err: err.message }));

    io = new SocketServer(httpServer, {
        cors: {
            // Socket.io connections are authenticated via JWT token in the handshake.
            // CORS is not a meaningful security boundary here — allow all origins so
            // native mobile clients (Flutter Android/iOS) can connect regardless of
            // what Origin header (if any) the socket_io_client sends.
            origin: true,
            methods: ['GET', 'POST'],
            credentials: true,
        },
    });

    // Activar Redis adapter si está disponible
    if (redisPub && redisSub) {
        io.adapter(createAdapter(redisPub, redisSub));
        logger.info('Socket.io usando Redis adapter');
    } else {
        logger.info('Socket.io usando adapter in-memory (sin REDIS_URL)');
    }

    io.use((socket, next) => {
        const token = socket.handshake.auth.token as string;
        if (!token) return next(new Error('No token'));
        try {
            const decoded = jwt.verify(token, env.JWT_SECRET) as { userId: string; role: string };
            socket.data.userId = decoded.userId;
            socket.data.role = decoded.role;
            next();
        } catch {
            next(new Error('Invalid token'));
        }
    });

    io.on('connection', (socket) => {
        logger.info('Socket connected', { userId: socket.data.userId });

        socket.on('join_booking', async (bookingId: string) => {
            const userId = socket.data.userId as string;
            if (!bookingId || typeof bookingId !== 'string') {
                socket.emit('error', { message: 'bookingId inválido' });
                return;
            }
            // Verificar que el usuario es cliente o cuidador de esta reserva
            const booking = await prisma.booking.findFirst({
                where: {
                    id: bookingId,
                    OR: [
                        { clientId: userId },
                        { caregiver: { userId } },
                    ],
                },
                select: { id: true },
            }).catch(() => null);

            if (!booking) {
                socket.emit('error', { message: 'No tienes acceso a esta reserva' });
                logger.warn('Socket join_booking denegado', { userId, bookingId });
                return;
            }
            socket.join(`booking:${bookingId}`);
            logger.info('User joined booking room', { userId, bookingId });
        });

        socket.on('send_message', async (data: { bookingId: string; message: string }) => {
            try {
                const { bookingId, message } = data;
                if (!message?.trim()) return;

                const booking = await prisma.booking.findFirst({
                    where: {
                        id: bookingId,
                        OR: [
                            { clientId: socket.data.userId },
                            { caregiver: { userId: socket.data.userId } },
                        ],
                    },
                    include: {
                        caregiver: { select: { userId: true } },
                    },
                });

                if (!booking) {
                    socket.emit('error', { message: 'No tienes acceso a este chat' });
                    return;
                }

                // Bloqueo: si cualquiera de las dos partes bloqueó a la otra, no se
                // puede enviar mensajes. El endpoint REST (POST /chat/:bookingId/messages)
                // ya validaba esto, pero el socket permitía evadirlo enviando por WS.
                const isClient = booking.clientId === socket.data.userId;
                const recipientId = isClient ? booking.caregiver.userId : booking.clientId;
                const blockExists = await prisma.userBlock.findFirst({
                    where: {
                        OR: [
                            { blockerId: socket.data.userId, blockedId: recipientId },
                            { blockerId: recipientId, blockedId: socket.data.userId },
                        ],
                    },
                });
                if (blockExists) {
                    socket.emit('error', { message: 'No puedes enviar mensajes a este usuario.' });
                    return;
                }

                const savedMessage = await prisma.chatMessage.create({
                    data: {
                        bookingId,
                        senderId: socket.data.userId,
                        senderRole: socket.data.role,
                        message: message.trim(),
                    },
                    include: {
                        sender: { select: { id: true, firstName: true, lastName: true } },
                    },
                });

                io!.to(`booking:${bookingId}`).emit('new_message', {
                    id: savedMessage.id,
                    bookingId: savedMessage.bookingId,
                    senderId: savedMessage.senderId,
                    senderName: `${savedMessage.sender.firstName} ${savedMessage.sender.lastName}`,
                    senderRole: savedMessage.senderRole,
                    message: savedMessage.message,
                    isSystem: savedMessage.isSystem,
                    read: savedMessage.read,
                    createdAt: savedMessage.createdAt.toISOString(),
                });

            } catch (err) {
                logger.error('Error saving message', { err });
                socket.emit('error', { message: 'Error al enviar mensaje' });
            }
        });

        socket.on('mark_read', async (bookingId: string) => {
            try {
                // A diferencia de join_booking/send_message, este handler no
                // verificaba que el socket perteneciera a la reserva — cualquier
                // usuario autenticado podía marcar como leídos los mensajes de
                // CUALQUIER booking adivinando/enumerando el bookingId.
                const booking = await prisma.booking.findFirst({
                    where: {
                        id: bookingId,
                        OR: [
                            { clientId: socket.data.userId },
                            { caregiver: { userId: socket.data.userId } },
                        ],
                    },
                    select: { id: true },
                }).catch(() => null);
                if (!booking) return;

                await prisma.chatMessage.updateMany({
                    where: {
                        bookingId,
                        senderId: { not: socket.data.userId },
                        read: false,
                    },
                    data: { read: true },
                });
                io!.to(`booking:${bookingId}`).emit('messages_read', {
                    bookingId,
                    readBy: socket.data.userId,
                });
            } catch (err) {
                logger.error('Error marking messages as read', { err });
            }
        });

        socket.on('disconnect', () => {
            logger.info('Socket disconnected');
        });
    });

    return io;
}

export function getIO(): SocketServer | null {
    return io;
}
