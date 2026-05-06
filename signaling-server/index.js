const express = require('express');
const http = require('http');
const socketIo = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

const users = new Map(); // userId -> socketId

io.on('connection', (socket) => {
  console.log('A user connected:', socket.id);

  socket.on('register', (data) => {
    const { userId } = data;
    users.set(userId, socket.id);
    console.log(`User registered: ${userId} with socket: ${socket.id}`);
    socket.broadcast.emit('user-joined', { userId });
  });

  socket.on('offer', (data) => {
    const { to, from, sdp } = data;
    const targetSocketId = users.get(to);
    if (targetSocketId) {
      io.to(targetSocketId).emit('offer', { from, sdp });
      console.log(`Offer sent from ${from} to ${to}`);
    }
  });

  socket.on('answer', (data) => {
    const { to, from, sdp } = data;
    const targetSocketId = users.get(to);
    if (targetSocketId) {
      io.to(targetSocketId).emit('answer', { from, sdp });
      console.log(`Answer sent from ${from} to ${to}`);
    }
  });

  socket.on('ice-candidate', (data) => {
    const { to, from, candidate } = data;
    const targetSocketId = users.get(to);
    if (targetSocketId) {
      io.to(targetSocketId).emit('ice-candidate', { from, candidate });
      console.log(`ICE Candidate sent from ${from} to ${to}`);
    }
  });

  socket.on('disconnect', () => {
    for (const [userId, socketId] of users.entries()) {
      if (socketId === socket.id) {
        users.delete(userId);
        console.log(`User disconnected: ${userId}`);
        socket.broadcast.emit('user-left', { userId });
        break;
      }
    }
  });
});

const PORT = process.env.PORT || 8080;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Signaling server running on port ${PORT}`);
});
