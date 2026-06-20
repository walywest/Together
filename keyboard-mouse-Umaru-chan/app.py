from tkinter import *
from tkinter import PhotoImage
from tkinter import ttk
from PIL import Image, ImageTk
import tkinter

from mouse import end_coord



def update_mouse_position():
    coords = end_coord()
    x,y = coords
    canvas.coords(mouseId, x, y)
    
    root.after(50, update_mouse_position)


root = Tk()     # создаем корневой объект - окно
root.title("Keyboard&Mouse")     # устанавливаем заголовок окна
root.geometry("300x250")    # устанавливаем размеры окна
root.iconbitmap(default="public/favicon.ico")

canvas = Canvas(bg="white", width=250, height=200)
canvas.pack(anchor=CENTER, expand=1)

# picture base
image = Image.open("public/base.jpg")  # Replace with your image file path
resized_image = image.resize((250, 200))

img = ImageTk.PhotoImage(resized_image)

canvas.create_image(10, 10, anchor=NW, image=img)

# picture mouse
image_mouse = Image.open("public/mouse.png")  # Replace with your image file path
resized_image_mouse = image_mouse.resize((50, 50))

img_mouse = ImageTk.PhotoImage(resized_image_mouse)

mouseId=canvas.create_image(10, 10, anchor=NW, image=img_mouse)



# Запускаем цикл обновления позиции мыши
root.after(100, update_mouse_position)

root.mainloop()