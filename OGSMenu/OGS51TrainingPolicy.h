#pragma once
#include <cmath>
namespace ogs51 {
struct Point {float x=0,y=0,z=0;};
inline bool visible(Point p,double age) {
 return std::isfinite(p.x)&&std::isfinite(p.y)&&std::isfinite(p.z)&&p.z>.05f&&
 p.x>=0&&p.x<=1&&p.y>=0&&p.y<=1&&std::isfinite(age)&&age>=0&&age<=.25;
}
inline bool listSize(int size,int selected,unsigned long capacity) {
 return size>=0&&size<=64&&capacity>=static_cast<unsigned>(size)&&capacity<=1024&&selected>=-1&&selected<size;
}
}
