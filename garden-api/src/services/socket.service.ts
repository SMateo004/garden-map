import { Server as SocketServer } from 'socket.io';
import { Server as HttpServer } from 'http';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import prisma from '../config/database.js';
import logger from '../shared/logger.js';

let io: SocketServer | null = null;

export function initSocketServer(httpServer: HttpServer): SocketServer {
    io = new SocketServer(httpServer, {
        cors: {
            origin: '*',
            methods: ['GET', 'POST'],
        },
    });

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

        socket.on('join_booking', (bookingId: string) => {
            socket.join(`booking:${bookingId}`);
            logger.info('User joined booking room', { userId: socket.data.userId, bookingId });
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
                });

                if (!booking) {
                    socket.emit('error', { message: 'No tienes acceso a este chat' });
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
