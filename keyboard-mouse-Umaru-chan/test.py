import numpy as np

# Координаты всех точек
points = [(30, 100), (110, 110), (70, 160), (0, 130)]

# Находим min/max координат
min_x = min(x for x, y in points)
max_x = max(x for x, y in points) 
min_y = min(y for x, y in points)
max_y = max(y for x, y in points)

print(f"Bounding box: ({min_x}, {min_y}) - ({max_x}, {max_y})")
# Bounding box: (0, 100) - (110, 160)



def normalize_mouse_to_region(mouse_x, mouse_y, screen_width, screen_height):
    """
    Нормализует координаты мыши из системных в координаты области
    """
    # Нормализуем в диапазон [0, 1] относительно bounding box
    norm_x = (mouse_x / screen_width)
    norm_y = (mouse_y / screen_height)
    
    # Масштабируем до размеров bounding box области
    region_width = 110 - 0  # max_x - min_x
    region_height = 160 - 100  # max_y - min_y
    
    scaled_x = 0 + norm_x * region_width
    scaled_y = 100 + norm_y * region_height
    
    return scaled_x, scaled_y

def rotate_coordinates(x, y, angle_degrees, center_x=55, center_y=130):
    """
    Поворачивает координаты на заданный угол вокруг центра
    center_x, center_y - приблизительный центр области
    """
    # Переводим в радианы
    angle_rad = np.radians(angle_degrees)
    
    # Смещаем координаты относительно центра
    x_centered = x - center_x
    y_centered = y - center_y
    
    # Поворачиваем
    x_rotated = x_centered * np.cos(angle_rad) - y_centered * np.sin(angle_rad)
    y_rotated = x_centered * np.sin(angle_rad) + y_centered * np.cos(angle_rad)
    
    # Возвращаем обратно
    return x_rotated + center_x, y_rotated + center_y


def transform_mouse_coordinates(mouse_x, mouse_y, screen_width, screen_height):
    """
    Полное преобразование координат мыши
    """
    # 1. Нормализуем в область
    region_x, region_y = normalize_mouse_to_region(mouse_x, mouse_y, screen_width, screen_height)
    
    # 2. Поворачиваем на 135 градусов
    rotated_x, rotated_y = rotate_coordinates(region_x, region_y, 210)
    
    return rotated_x, rotated_y

def draw_mouse_vector(start_x, start_y, vector_x, vector_y, screen_width, screen_height):
    """
    Рисует вектор движения мыши на фрейме
    """
    # Преобразуем начальную точку
    start_transformed = transform_mouse_coordinates(start_x, start_y, screen_width, screen_height)
    
    # Преобразуем конечную точку (start + vector)
    end_x = start_x + vector_x
    end_y = start_y + vector_y
    end_transformed = transform_mouse_coordinates(end_x, end_y, screen_width, screen_height)
    
        
    return (int(end_transformed[0]), int(end_transformed[1]))
    