import time
from pynput.mouse import Button, Controller
from test import draw_mouse_vector


mouse = Controller()

def vector():
    begin = mouse.position
    end = mouse.position

    x = end[0] - begin[0]
    y = end[1] - begin[1]
    return (x,y)

def end_coord():
    screen_width = 2560   # ширина вашего экрана
    screen_height = 1440  # высота вашего экрана

    # Текущие координаты мыши (например, из pyautogui)
    current_mouse_x = mouse.position[0]
    current_mouse_y = mouse.position[1]

    # Вектор движения мыши (разность между текущей и предыдущей позицией)
    vector_val = vector()
    vector_x = vector_val[0]   # смещение по X
    vector_y = vector_val[1]   # смещение по Y

    # Получаем конечные координаты после преобразования
    end_point = draw_mouse_vector(
        start_x=current_mouse_x,
        start_y=current_mouse_y, 
        vector_x=vector_x,
        vector_y=vector_y,
        screen_width=screen_width,
        screen_height=screen_height
    )
    return end_point

    
    

if __name__ == "__main__":
    while True:
        a = end_coord()
        print(f"Конечные координаты: {a}")
